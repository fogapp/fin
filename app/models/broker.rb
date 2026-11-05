# typed: true

class Broker < ApplicationRecord
  include HouseholdScoped
  has_many :accounts, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }
end
