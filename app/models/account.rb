# typed: true

class Account < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion
  include EmitsWorkflowEvents
  include ReferencedByWorkflowSteps
  flags_orphaned_workflow_steps "assign_account", param: "account_id", action_label: "assign account"
  flags_orphaned_workflow_steps "transfer_to_account", param: "account_id", action_label: "transfer to account"

  # "standard" accounts are synced/tracked and require a broker; "external"
  # accounts represent real accounts the system doesn't sync (created with
  # just a name, used as the counterparty of one-sided transfers). They
  # carry no balance and are excluded from net-worth math.
  class Kind < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Standard = new("standard")
      External = new("external")
    end
  end

  # Tax character of the account, set once by the user. Powers the tax
  # center: contribution tracking (transfers into retirement/HSA/529
  # accounts vs annual limits) and the wash-sale scanner's
  # permanent-disallowance warning (Rev. Rul. 2008-5) for repurchases
  # inside retirement accounts.
  class TaxTreatment < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Taxable = new("taxable")
      Traditional401k = new("traditional_401k")
      TraditionalIra = new("traditional_ira")
      Roth401k = new("roth_401k")
      RothIra = new("roth_ira")
      Hsa = new("hsa")
      Education = new("education")
      Other = new("other")
    end
  end

  RETIREMENT_TREATMENTS = T.let(
    [ TaxTreatment::Traditional401k, TaxTreatment::TraditionalIra,
      TaxTreatment::Roth401k, TaxTreatment::RothIra ].freeze,
    T::Array[TaxTreatment]
  )

  typed_enum :kind, Kind
  typed_enum :tax_treatment, TaxTreatment

  belongs_to :broker, optional: true
  has_many :investment_transactions, dependent: :restrict_with_error
  has_many :position_snapshots, dependent: :restrict_with_error
  has_many :cash_transactions, dependent: :nullify
  has_many :plaid_accounts, dependent: :nullify

  before_validation :generate_external_account_number

  validates :name, :account_number, presence: true
  validates :account_number, uniqueness: { scope: :broker_id }
  validates :broker, presence: true, unless: :external?

  sig { returns(T::Boolean) }
  def external? = kind == Kind::External

  # After a manual balance edit: snapshot the new balance and record the
  # delta as an adjustment transaction so cash history still sums correctly.
  # Call inside the same transaction as the balance update.
  def record_manual_balance_change!(old_balance)
    return if balance.blank?

    AccountBalanceSnapshot.record(self, source: AccountBalanceSnapshot::Source::Manual)
    return if old_balance.blank?

    delta = balance.to_d - old_balance.to_d
    return if delta.zero?

    CashTransaction.create!(
      source:           :bank,
      transaction_date: Date.current,
      post_date:        Date.current,
      description:      "Manual Adjustment",
      amount:           delta,
      transaction_type: CashTransaction::TransactionType::ManualAdjustment.serialize,
      account:          self,
      source_row_hash:  "manual_adjustment_#{id}_#{Time.current.to_f}"
    )
  end

  private

  # External accounts are created with just a name; satisfy the NOT NULL +
  # per-broker uniqueness constraints with a generated number.
  def generate_external_account_number
    return unless external? && account_number.blank?

    self.account_number = "ext-#{SecureRandom.hex(4)}"
  end
end
