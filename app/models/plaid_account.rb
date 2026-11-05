# typed: true

class PlaidAccount < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  belongs_to :plaid_item
  belongs_to :account, optional: true

  validates :plaid_account_id, presence: true, uniqueness: true
  validates :name, presence: true

  # Plaid investment subtypes whose value lives entirely in holdings — Plaid
  # reports balances.current = 0 at the account level for these.
  CRYPTO_WALLET_SUBTYPES = [ "non-custodial wallet", "crypto exchange" ].freeze

  sig { returns(T::Boolean) }
  def linked?
    account_id.present?
  end

  sig { returns(T::Boolean) }
  def credit?
    account_subtype == "credit card"
  end

  sig { returns(T::Boolean) }
  def crypto_wallet?
    CRYPTO_WALLET_SUBTYPES.include?(account_subtype)
  end

  sig { returns(String) }
  def display_name
    mask.present? ? "#{name} (•••#{mask})" : name
  end

  sig { returns(Account) }
  def link_to_new_account!
    return T.must(account) if linked?

    broker = T.must(household).brokers.find_or_create_by!(
      name: T.must(plaid_item).institution_name.presence || "Unknown"
    )

    # On reconnect, an Account from the previous connection may already exist
    # (orphaned when the old PlaidItem was destroyed). Relink to it instead of
    # creating a duplicate.
    candidate_number = mask.present? ? "****#{mask}" : nil
    if candidate_number
      orphaned = broker.accounts
        .left_joins(:plaid_accounts)
        .where(plaid_accounts: { id: nil })
        .find_by(account_number: candidate_number)
      if orphaned
        update!(account: orphaned)
        T.must(plaid_item).update!(cursor: nil)
        return orphaned
      end
    end

    number = unique_account_number_for(broker)
    new_account = T.must(household).accounts.create!(
      name:           name,
      account_number: number,
      account_type:   self.class.map_account_type(account_type.to_s, account_subtype),
      broker:         broker
    )
    update!(account: new_account)
    T.must(plaid_item).update!(cursor: nil)
    new_account
  end

  sig { params(type: String, subtype: T.nilable(String)).returns(String) }
  def self.map_account_type(type, subtype)
    case type
    when "depository"
      case subtype
      when "checking" then "Checking"
      when "savings", "money market", "cd" then "Savings"
      else "Other"
      end
    when "credit"     then "Credit Card"
    when "investment"
      if CRYPTO_WALLET_SUBTYPES.include?(subtype.to_s)
        "Crypto"
      elsif subtype.to_s.match?(/ira|401k|roth|retirement/i)
        "Retirement"
      else
        "Brokerage"
      end
    when "loan"       then "Other"
    else                   "Other"
    end
  end

  private

  sig { params(broker: Broker).returns(String) }
  def unique_account_number_for(broker)
    base = mask.present? ? "****#{mask}" : "****#{plaid_account_id.to_s.last(4)}"
    return base unless broker.accounts.exists?(account_number: base)

    suffix = 2
    suffix += 1 while broker.accounts.exists?(account_number: "#{base}-#{suffix}")
    "#{base}-#{suffix}"
  end
end
