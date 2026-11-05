# typed: true

class Household < ApplicationRecord
  has_many :household_memberships, dependent: :destroy
  has_many :users, through: :household_memberships
  has_many :api_tokens, dependent: :destroy
  has_many :invite_codes, dependent: :destroy

  has_many :accounts,                dependent: :destroy
  has_many :brokers,                 dependent: :destroy
  has_many :categories,              dependent: :destroy
  has_many :tags,                    dependent: :destroy
  has_many :merchants,               dependent: :destroy
  has_many :merchant_rules,          dependent: :destroy
  has_many :cash_transactions,       dependent: :destroy
  has_many :investment_transactions, dependent: :destroy
  has_many :position_snapshots,      dependent: :destroy
  has_many :transfers,               dependent: :destroy
  has_many :csv_imports,             dependent: :destroy
  has_many :recurring_series,        dependent: :destroy
  has_many :recurring_occurrences,   dependent: :destroy
  has_many :saved_views,             dependent: :destroy
  has_many :plaid_items,             dependent: :destroy
  has_many :plaid_accounts,          dependent: :destroy
  has_many :plaid_configurations,    dependent: :destroy
  has_many :alchemy_configurations,  dependent: :destroy
  has_many :alchemy_wallets,         dependent: :destroy

  validates :name, presence: true

  typed_enum :workflow_log_level, Workflows::LogLevel
end
