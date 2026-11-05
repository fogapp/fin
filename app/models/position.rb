# typed: true

# A ledger-derived position: what the transaction history says you hold in
# one account. Rebuilt idempotently by Positions::Rebuild; reconciled
# against custodian observations (position_snapshots) by the reconciliation
# engine. Never written incrementally.
class Position < ApplicationRecord
  include HouseholdScoped

  belongs_to :account
  belongs_to :security

  validates :quantity, presence: true

  scope :open, -> { where("quantity > 0") }
end
