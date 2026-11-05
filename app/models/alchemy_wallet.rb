# typed: true

class AlchemyWallet < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  belongs_to :account, optional: true
  has_many :alchemy_wallet_syncs, dependent: :destroy

  # Networks the Alchemy Portfolio API can query (max 5 per address/request).
  SUPPORTED_NETWORKS = %w[eth-mainnet base-mainnet polygon-mainnet arb-mainnet opt-mainnet].freeze

  # Native (gas) token per network; token entries with a null tokenAddress.
  NATIVE_TOKENS = {
    "eth-mainnet"     => { ticker: "ETH",   name: "Ethereum" },
    "base-mainnet"    => { ticker: "ETH",   name: "Ethereum" },
    "polygon-mainnet" => { ticker: "MATIC", name: "Polygon" },
    "arb-mainnet"     => { ticker: "ETH",   name: "Ethereum" },
    "opt-mainnet"     => { ticker: "ETH",   name: "Ethereum" }
  }.freeze

  before_validation :normalize_address

  validates :address, presence: true,
                      format: { with: /\A0x[0-9a-f]{40}\z/, message: "must be a 0x-prefixed EVM address" },
                      uniqueness: { scope: :household_id }
  validate :networks_supported

  scope :active, -> { where(active: true) }

  sig { returns(String) }
  def display_name
    name.presence || "Wallet #{address.last(4)}"
  end

  # The linked Account, created on first use. Uses the address as the
  # account number so a re-added wallet relinks to the same account.
  sig { returns(Account) }
  def ensure_account!
    return T.must(account) if account.present?

    broker = T.must(household).brokers.find_or_create_by!(name: "Self-Custody")
    existing = broker.accounts.find_by(account_number: address)
    new_account = existing || T.must(household).accounts.create!(
      name:           display_name,
      account_number: address,
      account_type:   "Crypto",
      broker:         broker
    )
    update!(account: new_account)
    new_account
  end

  private

  sig { void }
  def normalize_address
    self.address = address.to_s.strip.downcase
  end

  sig { void }
  def networks_supported
    list = Array(networks)
    errors.add(:networks, "must include at least one network") if list.empty?
    unsupported = list - SUPPORTED_NETWORKS
    errors.add(:networks, "unsupported: #{unsupported.join(', ')}") if unsupported.any?
  end
end
