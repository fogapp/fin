# typed: true

class Tag < ApplicationRecord
  include HouseholdScoped
  # Tag renames/deletes change tag-filtered cashflow responses, which are
  # cached with tag_id in the key.
  include BumpsHouseholdDataVersion
  include ReferencedByWorkflowSteps
  flags_orphaned_workflow_steps "add_tag", param: "tag_id", action_label: "add tag"
  has_many :cash_transaction_tags, dependent: :destroy
  has_many :cash_transactions, through: :cash_transaction_tags

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }

  before_save { T.unsafe(self).name = T.must(name).strip }
end
