# typed: strict

module Positions
  # Idempotently rebuilds the ledger position for one (account, security)
  # pair from the FULL transaction history. Deletes the row when the
  # position nets to zero or below.
  module Rebuild
    extend T::Sig

    # Direction groups: on-chain transfers move quantity and basis exactly
    # like trades do, but stay out of buy/sell/invested/proceeds stats.
    INBOUND_CATEGORIES  = T.let(
      [ ::TransactionType::Category::PURCHASE, ::TransactionType::Category::TRANSFER_IN ].freeze, T::Array[String]
    )
    OUTBOUND_CATEGORIES = T.let(
      [ ::TransactionType::Category::SALE, ::TransactionType::Category::TRANSFER_OUT ].freeze, T::Array[String]
    )
    POSITION_CATEGORIES = T.let((INBOUND_CATEGORIES + OUTBOUND_CATEGORIES).freeze, T::Array[String])

    sig { params(account: Account, security: Security).returns(T.nilable(Position)) }
    def self.call(account:, security:)
      apply(account, Ledger.totals(account_id: account.id, security_id: security.id),
            Position.find_or_initialize_by(account_id: account.id, security_id: security.id))
    end

    sig { params(account: Account, totals: Ledger::Totals, position: Position).returns(T.nilable(Position)) }
    def self.apply(account, totals, position)
      if totals.quantity <= 0
        position.destroy! if position.persisted?
        return nil
      end

      position.assign_attributes(
        household_id:      account.household_id,
        quantity:          totals.quantity.round(8),
        cost_basis:        totals.cost.round(4),
        first_acquired_on: totals.first_acquired_on,
        ledger_updated_at: Time.current
      )
      position.save!
      position
    end
    private_class_method :apply

    # Rebuild every pair that has any position-relevant ledger activity.
    sig { params(household: T.nilable(Household)).returns(Integer) }
    def self.all(household: nil)
      scope = InvestmentTransaction
        .joins(:transaction_type)
        .where(transaction_types: { category: POSITION_CATEGORIES })
        .where.not(account_id: nil).where.not(security_id: nil)
      scope = scope.where(accounts: { household_id: household.id }).joins(:account) if household

      pairs = scope.distinct.pluck(:account_id, :security_id)
      return 0 if pairs.empty?

      # Everything the pairs need, read once rather than per pair.
      account_ids = pairs.map(&:first).uniq
      accounts    = Account.unscoped.where(id: account_ids).index_by(&:id)
      securities  = Security.where(id: pairs.map(&:last).uniq).index_by(&:id)
      totals      = Ledger.totals_by_pair(InvestmentTransaction.where(account_id: account_ids))
      positions   = Position.where(account_id: account_ids).index_by { |p| [ p.account_id, p.security_id ] }
      households  = Household.where(id: accounts.values.map(&:household_id).uniq).index_by(&:id)

      pairs.each do |account_id, security_id|
        account  = accounts[account_id]
        security = securities[security_id]
        next unless account && security

        # A new row gets the loaded records, so its belongs_to checks don't
        # read them back one by one.
        position = positions[[ account_id, security_id ]] ||
                   Position.new(account: account, security: security, household: households[account.household_id])
        apply(account, totals.fetch([ account_id, security_id ]) { Ledger.totals(account_id:, security_id:) }, position)
      end
      pairs.size
    end
  end
end
