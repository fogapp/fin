# typed: true

module Alchemy
  # Pulls the full on-chain transfer history for one (wallet, network) pair,
  # from block 0 up to the backfill_target_block frozen when the pair was
  # first seen. PageKey-driven and resumable: the cursor persists after every
  # ingested page, each perform is bounded to MAX_PAGES_PER_RUN and
  # self-chains for the rest, so a transient failure re-runs at most one
  # bounded slice.
  class BackfillJob < ApplicationJob
    extend T::Sig

    queue_as :backfill
    limits_concurrency to: 1, key: ->(wallet_id, network) { "alchemy_backfill:#{wallet_id}:#{network}" }

    MAX_PAGES_PER_RUN = 25
    PAGE_PAUSE = 0.3   # rate courtesy: getAssetTransfers is 120 CU per call
    CANDLE_PAUSE = 6.0 # keyless CoinGecko allows ~10 calls/min; match MarketData::Scheduler pacing

    sig { params(wallet_id: String, network: String).void }
    def perform(wallet_id, network)
      with_record(AlchemyWallet, wallet_id) do |wallet|
        next unless wallet.active?

        state = AlchemyWalletSync.find_or_create_by!(
          alchemy_wallet: wallet, network: network, household_id: wallet.household_id
        )
        return if state.backfill_completed?

        client = RpcClient.new(network: network)
        ensure_target!(state, client)
        state.update!(backfill_status: AlchemyWalletSync::BackfillStatus::Running, last_error: nil)
        ensure_price_history(wallet)

        finished = run_pages(wallet, network, state, client)
        if finished
          state.update!(backfill_status: AlchemyWalletSync::BackfillStatus::Completed, backfill_cursor: {})
          finalize!(wallet, network, state)
        else
          self.class.perform_later(wallet_id, network)
        end
      rescue => e
        state&.update_columns(backfill_status: "failed", last_error: e.message.truncate(255))
        raise
      end
    end

    private

    # Pin the block range if the syncer hasn't seen this pair yet (e.g. a
    # manual backfill request right after wallet creation).
    # client: T.untyped so instance doubles pass the runtime sig in specs.
    sig { params(state: AlchemyWalletSync, client: T.untyped).void }
    def ensure_target!(state, client)
      return if state.backfill_target_block.present?

      safe_head = client.block_number - Networks.confirmation_depth(state.network)
      state.update!(
        backfill_target_block: safe_head,
        last_synced_block:     state.last_synced_block || safe_head,
        last_synced_at:        state.last_synced_at || Time.current
      )
    end

    sig do
      params(wallet: AlchemyWallet, network: String, state: AlchemyWalletSync, client: T.untyped)
        .returns(T::Boolean)
    end
    def run_pages(wallet, network, state, client)
      cursor    = state.backfill_cursor.presence || { "direction" => "from", "page_key" => nil }
      direction = T.let(cursor["direction"], T.nilable(String))
      page_key  = T.let(cursor["page_key"], T.nilable(String))
      target    = T.must(state.backfill_target_block)
      ingestor  = TransferIngestor.new
      pages     = 0

      # Historical rows must not fire user workflows (hundreds of
      # transaction.created events per deep wallet) — same suppression
      # precedent as Reconciliation::AcceptBalance.
      Workflows::Events.suppress do
        while direction && pages < MAX_PAGES_PER_RUN
          page = client.asset_transfers(address: wallet.address, direction: direction.to_sym,
                                        from_block: 0, to_block: target, page_key: page_key)
          result = ingestor.call(wallet: wallet, network: network, raw_transfers: page.transfers)
          result.skipped.each { |reason, n| skip_tallies[reason] = skip_tallies[reason].to_i + n }
          pages += 1

          if page.page_key
            page_key = page.page_key
          elsif direction == "from"
            direction, page_key = "to", nil
          else
            direction = nil
          end

          # Persist AFTER the ingest so a crash never skips a page.
          state.update!(
            backfill_cursor:         direction ? { "direction" => direction, "page_key" => page_key } : {},
            backfill_transfer_count: state.backfill_transfer_count + result.created
          )
          sleep(PAGE_PAUSE) if direction && pages < MAX_PAGES_PER_RUN
        end
      end

      direction.nil?
    end

    # Deep candle history for every token this wallet holds, so historical
    # transfers price at their trade date instead of today's quote. Held
    # crypto routes to CoinGecko, whose full sync fetches max history.
    sig { params(wallet: AlchemyWallet).void }
    def ensure_price_history(wallet)
      account = wallet.account
      return unless account

      security_ids = PositionSnapshot
        .where(account_id: account.id)
        .where("source_row_hash LIKE ?", "alchemy_wallet:#{wallet.id}:%")
        .distinct.pluck(:security_id)

      Security.where(id: security_ids).find_each do |security|
        oldest = Candle.daily.where(security_id: security.id).minimum(:date)
        next if oldest && oldest <= 2.years.ago.to_date # already deep

        link = MarketData::Router.link_for(security, MarketData::Capability::Candles)
        next unless link

        MarketData::Router.provider_instance(link.provider).sync_candles(security, link, full: true)
        sleep(CANDLE_PAUSE)
      rescue => e
        Rails.logger.warn("[Alchemy::BackfillJob] candle backfill failed for #{security.ticker}: #{e.message}")
      end
    end

    # Per-perform skip counters — surfaced in the completion Activity so a
    # backfill that quietly filters everything out is visible, not a mystery.
    sig { returns(T::Hash[Symbol, Integer]) }
    def skip_tallies
      @skip_tallies ||= T.let(Hash.new(0), T.nilable(T::Hash[Symbol, Integer]))
    end

    sig { params(wallet: AlchemyWallet, network: String, state: AlchemyWalletSync).void }
    def finalize!(wallet, network, state)
      skips = skip_tallies.reject { |_, n| n.zero? }
      Activity.record(
        source: "alchemy_transactions", event: "backfill.completed",
        severity: Severity::Info,
        summary: "Backfilled #{state.backfill_transfer_count} on-chain transfer(s) for " \
                 "#{wallet.display_name} on #{network}" \
                 "#{skips.any? ? " (skipped: #{skips.map { |k, v| "#{k}×#{v}" }.join(', ')})" : ''}",
        payload: { wallet_id: wallet.id, network: network,
                   transfers: state.backfill_transfer_count, skipped: skips }
      )

      # Wait until every network of this wallet has finished before the
      # expensive follow-ups: balances refresh, then a reconciliation sweep
      # so resolved drift Issues auto-clear.
      remaining = wallet.alchemy_wallet_syncs
        .where(network: wallet.networks)
        .where.not(backfill_status: "completed")
      return if remaining.exists?

      AlchemySyncJob.perform_later(wallet.household_id)
      Reconciliation::SweepJob.perform_later
    end
  end
end
