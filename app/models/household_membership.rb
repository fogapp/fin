# typed: true

class HouseholdMembership < ApplicationRecord
  extend T::Sig

  typed_enum :role, Role

  belongs_to :user
  belongs_to :household

  validates :user_id, uniqueness: { scope: :household_id }

  sig { returns(T::Boolean) }
  def admin?
    role == Role::Admin
  end
end
