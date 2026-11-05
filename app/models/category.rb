# typed: true

class Category < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion
  include EmitsWorkflowEvents
  include ReferencedByWorkflowSteps
  flags_orphaned_workflow_steps "assign_category", param: "category_id", action_label: "assign category"

  belongs_to :parent, class_name: "Category", optional: true
  has_many :subcategories, class_name: "Category", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent

  has_many :cash_transactions, dependent: :nullify
  has_many :merchants, dependent: :nullify

  # Flex-budgeting bucket: fixed bills, flexible spending, or non-monthly
  # (sinking funds — insurance, gifts, travel).
  class BudgetKind < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Fixed = new("fixed")
      Flex = new("flex")
      NonMonthly = new("non_monthly")
    end
  end

  typed_enum :budget_kind, BudgetKind

  validates :name, presence: true, uniqueness: { scope: [ :household_id, :parent_id ] }
  validate :parent_must_be_top_level

  private

  sig { void }
  def parent_must_be_top_level
    errors.add(:parent_id, "cannot be a subcategory") if parent&.parent_id.present?
  end
end
