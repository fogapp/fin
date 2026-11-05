# typed: true

class InvestmentTransaction < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion
  include EmitsWorkflowEvents
  include TransferLeg
  # Categories that carry real income into the account. Used to filter
  # income_usd sums so overloaded negative flows (capital calls, accrued
  # interest paid) don't net out the number. These match transaction_types
  # .category — an open reference table, not an owned enum.
  DIVIDEND_CATEGORIES = T.let(
    [ TransactionType::Category::DIVIDEND, TransactionType::Category::FOREIGN_DIVIDEND ].freeze, T::Array[String]
  )
  INCOME_CATEGORIES = T.let(
    (DIVIDEND_CATEGORIES + [ TransactionType::Category::INTEREST, TransactionType::Category::MUNICIPAL_INTEREST ]).freeze,
    T::Array[String]
  )

  belongs_to :account
  belongs_to :security, optional: true
  belongs_to :transaction_type

  validates :trade_date, :source_row_hash, presence: true
  validates :source_row_hash, uniqueness: true

  # Keep the ledger-derived position for this pair current. The rebuild is
  # idempotent, so bursts (imports, syncs) simply converge. (Single
  # after_commit form: the create/destroy sugar methods overwrite each other
  # when given the same method name.)
  after_commit :enqueue_position_rebuild, on: %i[create destroy]

  scope :recent,    -> { order(trade_date: :desc, id: :desc) }
  scope :income,    -> { joins(:transaction_type).where(transaction_types: { category: INCOME_CATEGORIES }) }
  scope :dividends, -> { joins(:transaction_type).where(transaction_types: { category: DIVIDEND_CATEGORIES }) }
  scope :purchases, -> { joins(:transaction_type).where(transaction_types: { category: TransactionType::Category::PURCHASE }) }
  scope :sales,     -> { joins(:transaction_type).where(transaction_types: { category: TransactionType::Category::SALE }) }

  private

  def enqueue_position_rebuild
    return if security_id.blank? || account_id.blank?
    return unless Positions::Rebuild::POSITION_CATEGORIES.include?(transaction_type&.category)

    Positions::RebuildJob.perform_later(T.must(account_id), T.must(security_id))
  end
end
