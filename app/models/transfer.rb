# typed: true

class Transfer < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion
  include EmitsWorkflowEvents
  TRANSACTION_TYPES = %w[CashTransaction InvestmentTransaction].freeze
  CANDIDATE_DAYS    = 3    # window for generic auto-detection
  # Payments get a wider window: the funding debit often posts 1-2 business
  # days after the card credit, and weekends/holidays stretch that.
  PAYMENT_CANDIDATE_DAYS = 4
  AMOUNT_TOLERANCE  = 0.01 # cents tolerance for matching

  # Identity: what kind of money movement this is. Payments are typed
  # transfers, not a parallel system (docs/credit-card-payments.md).
  class Kind < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Transfer = new("transfer")
      CreditCardPayment = new("credit_card_payment")
      LoanPayment = new("loan_payment")
    end
  end

  # Who confirmed the transfer: the user, auto-detection, or a workflow.
  class ConfirmationSource < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      User = new("user")
      Auto = new("auto")
      Workflow = new("workflow")
    end
  end

  PAYMENT_KINDS = T.let(
    [ Kind::CreditCardPayment, Kind::LoanPayment ].freeze,
    T::Array[Kind]
  )

  typed_enum :kind, Kind
  typed_enum :confirmation_source, ConfirmationSource, allow_nil: true

  belongs_to :counterparty_account, class_name: "Account", optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :from_transaction_type, :to_transaction_type,
            inclusion: { in: TRANSACTION_TYPES }, allow_blank: true
  validate  :sides_match_counterparty
  validate  :counterparty_is_valid
  validate  :sides_have_types_when_ids_present

  scope :confirmed,  -> { where.not(confirmed_at: nil) }
  scope :candidates, -> { where(confirmed_at: nil) }
  scope :payments,   -> { where(kind: PAYMENT_KINDS) }
  # Transfers with the given transaction on either side.
  scope :involving, ->(type, id) {
    where(from_transaction_type: type, from_transaction_id: id)
      .or(where(to_transaction_type: type, to_transaction_id: id))
  }
  # Transfers with this record (a TransferLeg) on either side.
  scope :referencing, ->(record) { involving(record.class.name, record.id) }
  # Unconfirmed candidates with a side that's gone or has since been linked
  # into a transfer — superseded, so detection clears them.
  scope :stale_candidates, -> {
    candidates.where("NOT (#{side_available_sql('from')} AND #{side_available_sql('to')})")
  }

  # Every [type, id] already on a side of some transfer — one query, for
  # callers that would otherwise ask .involving(...).exists? per transaction.
  sig { returns(T::Set[[ String, String ]]) }
  def self.linked_sides
    pluck(:from_transaction_type, :from_transaction_id, :to_transaction_type, :to_transaction_id)
      .each_with_object(Set.new) do |(from_type, from_id, to_type, to_id), set|
        set << [ from_type, from_id ] if from_id
        set << [ to_type, to_id ] if to_id
      end
  end

  # SQL: the side is empty, or names an existing transaction that isn't
  # linked to any transfer yet.
  sig { params(side: String).returns(String) }
  def self.side_available_sql(side)
    tables = { "CashTransaction" => "cash_transactions", "InvestmentTransaction" => "investment_transactions" }
    exists = tables.map do |type, table|
      "(transfers.#{side}_transaction_type = '#{type}' AND EXISTS (" \
        "SELECT 1 FROM #{table} WHERE #{table}.id = transfers.#{side}_transaction_id AND #{table}.transfer_id IS NULL))"
    end
    "(transfers.#{side}_transaction_id IS NULL OR #{exists.join(' OR ')})"
  end

  before_destroy :unlink_transactions

  sig { returns(T::Boolean) }
  def confirmed? = confirmed_at.present?

  sig { returns(T.nilable(T.any(CashTransaction, InvestmentTransaction))) }
  def from_transaction
    return nil unless from_transaction_id
    transaction_class(from_transaction_type)&.find_by(id: from_transaction_id)
  end

  sig { returns(T.nilable(T.any(CashTransaction, InvestmentTransaction))) }
  def to_transaction
    return nil unless to_transaction_id
    transaction_class(to_transaction_type)&.find_by(id: to_transaction_id)
  end

  sig { returns(T::Boolean) }
  def payment? = PAYMENT_KINDS.include?(kind)

  sig { params(source: ConfirmationSource).void }
  def confirm!(source: ConfirmationSource::User)
    # Atomic: a confirmed transfer without back-pointers would leave both
    # legs counted in spend/income despite being a confirmed pair.
    transaction do
      update!(confirmed_at: Time.current, confirmation_source: source)
      sync_transfer_ids
    end
  end

  sig { void }
  def sync_transfer_ids
    if from_transaction_id && (klass = transaction_class(from_transaction_type))
      klass.where(id: from_transaction_id).update_all(transfer_id: id)
    end
    if to_transaction_id && (klass = transaction_class(to_transaction_type))
      klass.where(id: to_transaction_id).update_all(transfer_id: id)
    end
  end

  private

  # Clear the denormalized back-pointer on both sides so a destroyed
  # transfer never leaves dangling transfer_ids.
  sig { void }
  def unlink_transactions
    TRANSACTION_TYPES.each do |type|
      T.must(type).constantize.where(transfer_id: id).update_all(transfer_id: nil)
    end
  end

  # Only ever constantize the two known transaction classes — the type
  # columns are mass-assigned from request params.
  sig do
    params(type: T.nilable(String))
      .returns(T.nilable(T.any(T.class_of(CashTransaction), T.class_of(InvestmentTransaction))))
  end
  def transaction_class(type)
    return nil unless TRANSACTION_TYPES.include?(type)

    T.must(type).constantize
  end

  # Pair transfers (both sides) stand alone; one-sided transfers must name
  # the counterparty account the money went to / came from.
  sig { void }
  def sides_match_counterparty
    from_present = from_transaction_id.present?
    to_present   = to_transaction_id.present?

    if !from_present && !to_present
      errors.add(:base, "Must have at least one transaction side")
    elsif from_present && to_present
      errors.add(:counterparty_account, "must be blank when both transaction sides are present") if counterparty_account_id.present?
    elsif counterparty_account_id.blank?
      errors.add(:counterparty_account, "is required for a one-sided transfer")
    end
  end

  sig { void }
  def counterparty_is_valid
    return if counterparty_account_id.blank?

    account = ::Account.unscoped.find_by(id: counterparty_account_id)
    if account.nil? || account.household_id != household_id
      errors.add(:counterparty_account, "must belong to the same household")
      return
    end

    side = from_transaction || to_transaction
    if side && side.account_id == counterparty_account_id
      errors.add(:counterparty_account, "must be a different account than the transaction's own")
    end
  end

  sig { void }
  def sides_have_types_when_ids_present
    if from_transaction_id.present? && from_transaction_type.blank?
      errors.add(:from_transaction_type, "must be set when from_transaction_id is present")
    end
    if to_transaction_id.present? && to_transaction_type.blank?
      errors.add(:to_transaction_type, "must be set when to_transaction_id is present")
    end
  end
end
