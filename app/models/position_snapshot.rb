# typed: true

class PositionSnapshot < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion
  include EmitsWorkflowEvents
  belongs_to :account
  belongs_to :security

  validates :as_of_date, :source_row_hash, presence: true
  validates :source_row_hash, uniqueness: true

  scope :chronological, -> { order(:as_of_date) }
end
