# typed: strict

module Positions
  # Writes the PositionSnapshots a holdings sync reports (Plaid, Alchemy
  # wallets, Coinbase balances) — the upsert, the zero-stamp of holdings
  # the source stopped reporting, and the holdings-derived account balance
  # the syncers each used to write for themselves.
  #
  # Rows are keyed by source_row_hash "<prefix>:<part>:<part>…", so a
  # re-sync updates the same row; the writer remembers every hash it wrote
  # so zero_stamp_missing! can tell which rows the source no longer reports.
  class SnapshotWriter
    extend T::Sig

    sig { returns(T::Set[String]) }
    attr_reader :seen

    sig { params(prefix: String, household_id: String, as_of: Date).void }
    def initialize(prefix:, household_id:, as_of: Date.current)
      @prefix       = T.let(prefix, String)
      @household_id = T.let(household_id, String)
      @as_of        = T.let(as_of, Date)
      @seen         = T.let(Set.new, T::Set[String])
    end

    sig { params(parts: T::Array[T.untyped]).returns(String) }
    def hash_for(parts)
      [ @prefix, *parts ].join(":")
    end

    # Creates or updates the snapshot for `parts` as of today.
    sig { params(parts: T::Array[T.untyped], attributes: T.untyped).returns(PositionSnapshot) }
    def upsert!(parts, **attributes)
      hash = hash_for(parts)
      @seen << hash
      PositionSnapshot.find_or_initialize_by(source_row_hash: hash).tap do |snap|
        snap.assign_attributes(household_id: @household_id, as_of_date: @as_of, **attributes)
        snap.save!
      end
    end

    # A holding the source stops reporting was sold or moved out. Its row
    # would otherwise keep the stale quantity forever, and
    # Reconciliation::AcceptBalance could recreate the sold position as an
    # adjustment. Zero-stamp it dated today — safer than deleting history,
    # and the newest observation then correctly reads quantity 0.
    #
    # `under` limits the sweep to rows beneath "<prefix>:<id>:" for each id
    # (the Plaid accounts of one item, one wallet), so one sync never
    # touches another source's rows. Row by row rather than update_all:
    # a sell-out is rare, and its snapshot update should still bump the
    # data version and publish position_snapshot.updated to workflows.
    sig do
      params(under: T::Array[String], skip_account_ids: T::Enumerable[String], clear_cost_basis: T::Boolean).void
    end
    def zero_stamp_missing!(under:, skip_account_ids: [], clear_cost_basis: false)
      return if under.empty?

      stale = PositionSnapshot
        .where(household_id: @household_id)
        .where("source_row_hash LIKE ANY (ARRAY[?])", under.map { |id| "#{hash_for([ id ])}:%" })
        .where.not(quantity: 0)
      stale = stale.where.not(source_row_hash: @seen.to_a) if @seen.any?
      stale = stale.where.not(account_id: skip_account_ids.to_a) if skip_account_ids.any?

      zeroed = { as_of_date: @as_of, quantity: 0, market_value: 0 }
      zeroed.merge!(cost_basis: nil, unrealized_gain_loss: nil, unrealized_gain_loss_pct: nil) if clear_cost_basis
      stale.find_each { |snap| snap.update!(zeroed) }
    end

    # Accounts whose only balance is their holdings (crypto wallets report
    # 0 or nothing) take the holdings' market value as their USD balance.
    sig { params(account: Account, total: BigDecimal, source: AccountBalanceSnapshot::Source).void }
    def self.set_holdings_balance!(account, total, source:)
      value = total.round(2)
      account.update_columns(balance: value, balance_currency: "USD", balance_usd: value)
      AccountBalanceSnapshot.record(account, balance: value, balance_currency: "USD", balance_usd: value, source: source)
    end
  end
end
