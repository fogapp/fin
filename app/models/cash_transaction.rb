# typed: true
# frozen_string_literal: true

class CashTransaction < ApplicationRecord
  extend T::Sig

  # The app's own transaction-type vocabulary — the values ingest normalizes
  # to (Plaid mapping, manual adjustments) and every scope/comparison keys
  # off. The column itself is OPEN: CSV importers pass bank "Type" values
  # through verbatim, so there is deliberately no typed_enum cast or
  # inclusion validation here. Readers return raw strings; compare against
  # `TransactionType::X.serialize`.
  class TransactionType < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Sale = new("Sale")
      Payment = new("Payment")
      Return = new("Return")
      AccountTransfer = new("Account Transfer")
      ManualAdjustment = new("Manual Adjustment")
    end
  end

  # Serialized values of the charge-shaped types, for scopes and raw SQL.
  CHARGE_TYPES = T.let(
    [ TransactionType::Sale, TransactionType::Return ].map(&:serialize).freeze,
    T::Array[String]
  )

  include HouseholdScoped
  include BumpsHouseholdDataVersion
  include TransferLeg
  belongs_to :loan, optional: true
  include ::EmitsWorkflowEvents
  enum :source, { bank: "bank", credit_card: "credit_card" }, prefix: true

  belongs_to :account, optional: true
  belongs_to :category, optional: true
  belongs_to :merchant, optional: true
  has_many :cash_transaction_tags, dependent: :destroy
  has_many :tags, through: :cash_transaction_tags
  has_one :recurring_occurrence, dependent: :nullify
  has_one :recurring_series, through: :recurring_occurrence

  validates :source, presence: true
  validates :amount, presence: true
  validates :transaction_date, presence: true
  validates :source_row_hash, presence: true, uniqueness: true

  scope :recent,    -> { order(transaction_date: :desc, created_at: :desc) }
  scope :sales,     -> { where(transaction_type: TransactionType::Sale.serialize) }
  scope :returns,   -> { where(transaction_type: TransactionType::Return.serialize) }
  scope :charges,   -> { where(transaction_type: CHARGE_TYPES) }

  # The app's definitions of income and spend, shared by the cashflow
  # summary and activity endpoints (they previously each had their own copy
  # of these SQL strings, which is how definitions fork).
  #
  # Income: bank deposits that aren't credit-card autopay noise or transfers.
  # Spend: credit-card sales/returns plus bank debits, minus autopay noise,
  # transfers, and excluded merchants.
  # Budget thresholds re-check when spend lands or moves category/amount.
  after_commit :enqueue_budget_check, on: %i[create update],
               if: -> { T.bind(self, CashTransaction); previous_changes.slice("amount", "category_id", "transaction_date").any? }
  # Payment detection probes every new row (the matcher pre-filters cheaply);
  # see Transfers::PaymentMatcher for the tiers.
  after_commit :enqueue_payment_match, on: :create

  # Exclusion is structural (docs/credit-card-payments.md §C) — linkage to a
  # confirmed Transfer, never description matching:
  #
  #   - Inflow legs of any linked transfer are excluded from income.
  #   - Outflow legs of linked transfers are excluded from spend UNLESS the
  #     transfer opts in via include_in_spend (cash-basis proxy for payments
  #     to untracked cards; budgetable loan payments).
  #   - Card-side payment credits carry transaction_type "Payment" from
  #     ingest, so they stay out of spend even before pairing.
  #
  # Unlinked bank-side payment legs count as spend until detection links them
  # (usually within minutes — Transfers::PaymentMatchJob); payment_suspects
  # surfaces anything that stays unlinked.
  scope :income_like, -> {
    source_bank
      .where("amount > 0")
      .where(transfer_id: nil)
  }
  scope :spend_like, -> {
    # Memoized per request/job (CurrentAttributes resets between them) —
    # cashflow evaluates this scope many times per request.
    excluded_ids = Current.excluded_merchant_ids ||= Merchant.excluded.pluck(:id)
    scope = where(
      "(source = 'credit_card' AND transaction_type IN (?)) OR " \
      "(source = 'bank' AND amount < 0)", CHARGE_TYPES
    ).where(
      "cash_transactions.transfer_id IS NULL OR " \
      "(cash_transactions.amount < 0 AND cash_transactions.transfer_id IN (SELECT id FROM transfers WHERE include_in_spend))"
    )
    # NULL-safe exclusion: `where.not(merchant_id: ids)` would also drop
    # rows with no merchant at all (SQL NOT IN vs NULL), silently removing
    # merchant-less transactions from spend whenever any merchant is excluded.
    excluded_ids.any? ? scope.where("merchant_id IS NULL OR merchant_id NOT IN (?)", excluded_ids) : scope
  }

  # Suspected unlinked payment legs still counted in spend — the data-quality
  # signal for the cashflow review chip. Bank debits that look like payments
  # (Plaid LOAN_PAYMENTS tag or a payment signature) but have no transfer.
  scope :payment_suspects, -> {
    source_bank
      .where("amount < 0")
      .where(transfer_id: nil)
      .where(
        "raw_category LIKE 'LOAN_PAYMENTS%' OR transaction_type = ? OR description ~* ?",
        TransactionType::Payment.serialize,
        Transfers::PaymentSignals::SIGNATURE_PATTERN.source
      )
  }

  sig { returns(T::Boolean) }
  def credit?
    amount.positive?
  end

  private

  def enqueue_budget_check
    return if Workflows::Events.suppressed?
    return if category_id.blank?

    Budgets::CheckThresholdsJob.perform_later(id)
  end

  def enqueue_payment_match
    return if Workflows::Events.suppressed?

    Transfers::PaymentMatchJob.perform_later(id)
  end
end
