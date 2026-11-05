# typed: true

class Merchant < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion
  include EmitsWorkflowEvents
  include ReferencedByWorkflowSteps
  flags_orphaned_workflow_steps "assign_merchant", param: "merchant_id", action_label: "assign merchant"

  # spend_like memoizes the excluded-merchant list for the request; a
  # merchant change mid-request must not serve the stale list.
  after_commit { Current.excluded_merchant_ids = nil }
  has_many :merchant_rules, -> { order(priority: :desc) }, dependent: :destroy
  has_many :cash_transactions, dependent: :nullify
  belongs_to :category, optional: true

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }

  scope :excluded, -> { where(excluded: true) }
end
