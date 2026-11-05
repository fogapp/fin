# typed: true

class PlaidItem < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  encrypts :access_token

  has_many :plaid_accounts, dependent: :destroy

  validates :item_id, :access_token, presence: true
  validates :item_id, uniqueness: true

  enum :status, { active: "active", error: "error" }, prefix: false

  sig { returns(String) }
  def display_name
    institution_name.presence || item_id
  end
end
