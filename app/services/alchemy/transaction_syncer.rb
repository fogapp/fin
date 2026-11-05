# typed: strict

module Alchemy
  # Incremental on-chain transaction sync. For each (wallet, network) pair it
  # walks getAssetTransfers forward from the stored cursor up to a
  # confirmation-depth-protected head, ingests both directions, and advances
  # the cursor only after a successful ingest (a crash refetches; the
  # idempotent ingestor absorbs the overlap).
  #
  # First sight of a pair pins the cursor at the safe head and hands
  # everything before it to Alchemy::BackfillJob — incremental sync walks
  # forward while backfill fills history behind it, so they never contend.
  class TransactionSyncer
    extend T::Sig

    Result = Struct.new(:pairs, :new_transfers, :errors, :touched_pairs, keyword_init: true)

    sig { params(wallets: T.untyped).returns(Result) }
    def call(wallets: AlchemyWallet.active)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result  = Result.new(pairs: 0, new_transfers: 0, errors: [], touched_pairs: Set.new)

      wallets.find_each do |wallet|
        wallet.networks.each do |network|
          sync_pair(wallet, network, result)
          result.pairs += 1
        rescue => e
          result.errors << { wallet: wallet.display_name, network: network, error: e.message }
          state_for(wallet, network).update_columns(last_error: e.message.truncate(255))
        end
      end

      if result.new_transfers.positive? || result.errors.any?
        Activity.record(
          source: "alchemy_transactions", event: "sync.completed",
          severity: result.errors.any? ? Severity::Warning : Severity::Info,
          summary: "On-chain transaction sync: #{result.new_transfers} new transfer(s) " \
                   "across #{result.pairs} wallet-network pair(s)" \
                   "#{result.errors.any? ? ", #{result.errors.size} errors" : ''}",
          payload: { pairs: result.pairs, new_transfers: result.new_transfers, errors: result.errors },
          duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        )
      end
      result
    end

    private

    sig { params(wallet: AlchemyWallet, network: String).returns(AlchemyWalletSync) }
    def state_for(wallet, network)
      AlchemyWalletSync.find_or_create_by!(
        alchemy_wallet: wallet, network: network, household_id: wallet.household_id
      )
    end

    sig { params(wallet: AlchemyWallet, network: String, result: Result).void }
    def sync_pair(wallet, network, result)
      state     = state_for(wallet, network)
      client    = RpcClient.new(network: network)
      safe_head = client.block_number - Networks.confirmation_depth(network)
      return if safe_head <= 0

      if state.last_synced_block.nil?
        # First sight: pin the cursor to the head and let backfill own history.
        state.update!(last_synced_block: safe_head, backfill_target_block: safe_head,
                      backfill_status: AlchemyWalletSync::BackfillStatus::Pending,
                      last_synced_at: Time.current)
        BackfillJob.perform_later(wallet.id, network)
        return
      end
      return if safe_head <= T.must(state.last_synced_block)

      transfers = fetch_range(client, wallet.address, T.must(state.last_synced_block) + 1, safe_head)
      ingested  = TransferIngestor.new.call(wallet: wallet, network: network, raw_transfers: transfers)

      state.update!(last_synced_block: safe_head, last_synced_at: Time.current, last_error: nil)
      result.new_transfers += ingested.created
      result.touched_pairs.merge(ingested.touched_pairs)
    end

    # client: T.untyped so instance doubles pass the runtime sig in specs.
    sig do
      params(client: T.untyped, address: String, from_block: Integer, to_block: Integer)
        .returns(T::Array[T.untyped])
    end
    def fetch_range(client, address, from_block, to_block)
      transfers = T.let([], T::Array[T.untyped])
      %i[from to].each do |direction|
        page_key = T.let(nil, T.nilable(String))
        loop do
          page = client.asset_transfers(address: address, direction: direction,
                                        from_block: from_block, to_block: to_block, page_key: page_key)
          transfers.concat(page.transfers)
          page_key = page.page_key
          break if page_key.nil?
        end
      end
      transfers
    end
  end
end
