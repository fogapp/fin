# typed: false

# Mixed into every household-scoped model. Provides:
#
#   - the belongs_to :household association
#   - a presence validation on household_id (the DB has NOT NULL, but the
#     model-side check produces a friendlier validation error)
#   - a default_scope that filters by Current.household when one is set
#   - a validation that every belongs_to pointing at another household-scoped
#     model references a row of this record's own household
#
# The default_scope only filters reads: assigning a foreign key never loads
# the target through it, so `account_id: <another household's account>` would
# save happily (the DB foreign keys are single-column). The reference check
# closes that write path for every model at once, whatever the caller.
#
# When Current.household is not set (background jobs without context, seeds,
# console, or unauthenticated specs), the default_scope is a no-op so callers
# can opt in explicitly via Current.set(household: ...) { ... } or .unscoped.
#
# Inside a request, Api::V1::BaseController#authenticate_with_token! sets
# Current.household before any action runs, so request handlers always see
# household-filtered data.
module HouseholdScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :household
    validates :household_id, presence: true
    default_scope { Current.household.present? ? where(household_id: Current.household.id) : all }
    before_validation :assign_household_from_current, on: :create
    validate :household_references_stay_in_household
  end

  private

  # Rejects a belongs_to whose foreign key names a household-scoped row of a
  # different household. Only keys that changed are checked (one indexed
  # EXISTS each), and an association already loaded with the same id is
  # compared in memory. A key naming no row at all is left to the database's
  # foreign key, as before.
  def household_references_stay_in_household
    return if household_id.blank?

    self.class.reflect_on_all_associations(:belongs_to).each do |reflection|
      next if reflection.polymorphic? || reflection.name == :household

      target_class = reflection.klass
      next unless target_class.include?(HouseholdScoped)

      foreign_key = reflection.foreign_key.to_s
      referenced_id = self[foreign_key]
      next if referenced_id.blank?
      next unless new_record? || will_save_change_to_attribute?(foreign_key)
      next unless referenced_in_other_household?(reflection, target_class, referenced_id)

      errors.add(reflection.name, "must belong to this household")
    end
  end

  def referenced_in_other_household?(reflection, target_class, referenced_id)
    association = association(reflection.name)
    target = association.loaded? ? association.target : nil
    if target && target.id == referenced_id && !target.household_id.nil?
      return target.household_id != household_id
    end

    target_class.unscoped.where(id: referenced_id).where.not(household_id: household_id).exists?
  end

  # Fills household_id from Current.household when a new record is created
  # inside a request context. Controllers can keep doing `Model.new(...)` /
  # `Model.create!(...)` without manually plumbing household_id; the value
  # always comes from the authenticated token, never from user input.
  def assign_household_from_current
    return if household_id.present?
    self.household = Current.household if Current.household
  end
end
