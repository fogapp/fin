# typed: strict

module Alchemy
  # Batch boundary between the sync/backfill jobs and the mapper: normalizes
  # raw getAssetTransfers records and ingests them idempotently. Returns
  # counts plus the (account_id, security_id) pairs that gained rows so
  # callers can trigger targeted follow-up work.
  class TransferIngestor
    extend T::Sig

    Result = Struct.new(:created, :duplicates, :skipped, :touched_pairs, keyword_init: true)

    sig { params(wallet: AlchemyWallet, network: String, raw_transfers: T::Array[T.untyped]).returns(Result) }
    def call(wallet:, network:, raw_transfers:)
      result = Result.new(created: 0, duplicates: 0, skipped: Hash.new(0), touched_pairs: Set.new)

      normalized = raw_transfers.map { |raw| normalize(raw) }

      # One page-wide context: dedupe hashes prefetched in a single query,
      # and resolver/price/type lookups memoized across the page.
      context = IngestContext.new(wallet: wallet)
      context.prefetch_existing!(
        normalized.flat_map do |t|
          %i[in out].map { |dir| TransferMapper.row_hash(network: network, unique_id: t[:unique_id].to_s, direction: dir) }
        end
      )

      normalized.each do |transfer|
        mapped = TransferMapper.call(wallet: wallet, network: network, transfer: transfer, context: context)
        case mapped.status
        when :created
          result.created += 1
          txn = mapped.transaction
          result.touched_pairs << [ txn.account_id, txn.security_id ]
        when :duplicate
          result.duplicates += 1
        else
          result.skipped[mapped.status] += 1
        end
      end

      result
    end

    private

    sig { params(raw: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def normalize(raw)
      {
        unique_id:        raw["uniqueId"],
        hash:             raw["hash"],
        block_num:        raw["blockNum"].to_s.to_i(16),
        from:             raw["from"].to_s.downcase,
        to:               raw["to"].to_s.downcase,
        value:            precise_value(raw),
        asset:            raw["asset"],
        category:         raw["category"],
        contract_address: raw.dig("rawContract", "address")&.downcase,
        block_timestamp:  raw.dig("metadata", "blockTimestamp")
      }
    end

    # The response's "value" field is a JSON float; recompute from the raw
    # hex amount + decimals so wei-level precision survives intact.
    sig { params(raw: T.untyped).returns(T.nilable(BigDecimal)) }
    def precise_value(raw)
      contract = raw["rawContract"] || {}
      if contract["value"].present?
        decimals = parse_decimals(contract["decimal"])
        return AlchemyClient.to_quantity(contract["value"], decimals) if decimals
      end
      raw["value"]&.to_d
    end

    sig { params(raw: T.untyped).returns(T.nilable(Integer)) }
    def parse_decimals(raw)
      str = raw.to_s
      return nil if str.blank?

      str.start_with?("0x") ? str[2..].to_s.to_i(16) : Integer(str, 10)
    rescue ArgumentError
      nil
    end
  end
end
