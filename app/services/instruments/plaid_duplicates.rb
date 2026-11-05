# typed: strict

module Instruments
  # Finds securities that Plaid forked in two.
  #
  # Before Instruments::Resolver, a Plaid sync created a Security per holding
  # with no identifiers at all. Once the resolver landed it keyed holdings on
  # plaid_security_id and minted a fresh row for each one, then kept syncing
  # into that. The abandoned row keeps the position it held on the day the
  # cutover happened — and CurrentPositions dedupes per (account, security),
  # so both rows survive and the portfolio counts the holding twice.
  #
  # A pair qualifies only when everything points one way: same account, same
  # security name, exactly one candidate carrying identifiers, the others
  # carrying none, and the identifier-less rows' observations stopping no
  # later than the survivor's. Anything ambiguous is reported, not merged.
  #
  # Snapshot reads go through the household default scope, so the audit job
  # sees one household at a time and the rake task (no Current.household)
  # sees them all.
  class PlaidDuplicates
    extend T::Sig

    class Pair < T::Struct
      const :keep, Security
      const :remove, Security
      const :account_id, String
      const :stale_as_of, T.nilable(Date)
      const :stale_market_value, Float
    end

    # One merge per duplicate row. A security held in several accounts forks
    # once but shows up as a pair per account, so the pairs collapse here —
    # merging the same row twice would operate on an already-destroyed record.
    class Plan < T::Struct
      const :keep, Security
      const :remove, Security
      const :account_ids, T::Array[String]
      const :stale_market_value, Float
    end

    class Skip < T::Struct
      const :name, String
      const :account_id, String
      const :security_ids, T::Array[String]
      const :reason, String
    end

    sig { returns(T::Array[Pair]) }
    attr_reader :pairs

    sig { returns(T::Array[Skip]) }
    attr_reader :skipped

    sig { void }
    def initialize
      @pairs   = T.let([], T::Array[Pair])
      @skipped = T.let([], T::Array[Skip])
      @scanned = T.let(false, T::Boolean)
    end

    sig { returns(PlaidDuplicates) }
    def call
      return self if @scanned

      @scanned = true
      grouped_candidates.each { |(account_id, _name), security_ids| classify(account_id, security_ids) }
      self
    end

    sig { returns(T::Array[Plan]) }
    def plans
      call

      @pairs.group_by { |pair| pair.remove.id }.filter_map do |_, group|
        keeps = group.map { |pair| pair.keep.id }.uniq
        first = T.must(group.first)
        if keeps.size > 1
          # The same abandoned row replaced by different securities in
          # different accounts isn't the fork this task understands.
          skip!(first.account_id, [ first.remove ], "duplicate maps to #{keeps.size} different keepers")
          next
        end

        Plan.new(
          keep:               first.keep,
          remove:             first.remove,
          account_ids:        group.map(&:account_id).uniq,
          stale_market_value: group.sum(0.0, &:stale_market_value)
        )
      end
    end

    private

    # (account, security name) => security ids, for every name an account
    # holds under more than one security row.
    sig { returns(T::Hash[[ String, String ], T::Array[String]]) }
    def grouped_candidates
      rows = PositionSnapshot.all
        .joins(:security)
        .where("position_snapshots.source_row_hash LIKE 'plaid_holding:%'")
        .distinct
        .pluck("position_snapshots.account_id", "securities.name", "position_snapshots.security_id")

      rows.group_by { |account_id, name, _| [ account_id.to_s, name.to_s ] }
          .transform_values { |group| group.map { |row| row[2].to_s }.uniq }
          .select { |_, ids| ids.size > 1 }
    end

    sig { params(account_id: String, security_ids: T::Array[String]).void }
    def classify(account_id, security_ids)
      securities = Security.where(id: security_ids).to_a
      identified, bare = securities.partition { |s| s.instrument_identifiers.any? }

      if identified.size != 1 || bare.empty?
        return skip!(account_id, securities, "expected exactly one identified row, got #{identified.size} of #{securities.size}")
      end

      keep = T.must(identified.first)
      keep_as_of = latest_as_of(keep.id, account_id)

      bare.each do |remove|
        stale_as_of = latest_as_of(remove.id, account_id)
        if keep_as_of.nil? || stale_as_of.nil? || stale_as_of > keep_as_of
          next skip!(account_id, [ keep, remove ], "duplicate is not stale (#{stale_as_of} vs #{keep_as_of})")
        end

        @pairs << Pair.new(
          keep:              keep,
          remove:            remove,
          account_id:        account_id,
          stale_as_of:       stale_as_of,
          stale_market_value: PositionSnapshot.all
                                .where(security_id: remove.id, account_id: account_id, as_of_date: stale_as_of)
                                .sum(:market_value).to_f
        )
      end
    end

    sig { params(security_id: String, account_id: String).returns(T.nilable(Date)) }
    def latest_as_of(security_id, account_id)
      PositionSnapshot.all.where(security_id: security_id, account_id: account_id).maximum(:as_of_date)
    end

    sig { params(account_id: String, securities: T::Array[Security], reason: String).void }
    def skip!(account_id, securities, reason)
      @skipped << Skip.new(
        name:         T.must(securities.first).name.to_s,
        account_id:   account_id,
        security_ids: securities.map { |s| s.id.to_s },
        reason:       reason
      )
    end
  end
end
