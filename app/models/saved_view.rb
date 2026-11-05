# typed: true

class SavedView < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  validates :name, presence: true
  validates :filter_params, presence: true
end
