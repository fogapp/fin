require "rails_helper"

RSpec.describe PlaidAccount do
  describe "associations" do
    it { is_expected.to belong_to(:plaid_item) }
    it { is_expected.to belong_to(:account).optional }
  end

  describe "validations" do
    subject { build(:plaid_account) }

    it { is_expected.to validate_presence_of(:plaid_account_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:plaid_account_id) }
  end

  describe "#linked?" do
    it "returns true when an account is associated" do
      account       = create(:account)
      plaid_account = build(:plaid_account, account: account)
      expect(plaid_account.linked?).to be true
    end

    it "returns false when no account is associated" do
      plaid_account = build(:plaid_account, account: nil)
      expect(plaid_account.linked?).to be false
    end
  end

  describe "#credit?" do
    it "returns true for credit card subtype" do
      plaid_account = build(:plaid_account, account_subtype: "credit card")
      expect(plaid_account.credit?).to be true
    end

    it "returns false for checking subtype" do
      plaid_account = build(:plaid_account, account_subtype: "checking")
      expect(plaid_account.credit?).to be false
    end
  end

  describe "#crypto_wallet?" do
    it "returns true for non-custodial wallet and crypto exchange subtypes" do
      expect(build(:plaid_account, account_subtype: "non-custodial wallet").crypto_wallet?).to be true
      expect(build(:plaid_account, account_subtype: "crypto exchange").crypto_wallet?).to be true
    end

    it "returns false for other subtypes" do
      expect(build(:plaid_account, account_subtype: "brokerage").crypto_wallet?).to be false
    end
  end

  describe ".map_account_type" do
    it "maps crypto wallet subtypes to Crypto" do
      expect(described_class.map_account_type("investment", "non-custodial wallet")).to eq("Crypto")
      expect(described_class.map_account_type("investment", "crypto exchange")).to eq("Crypto")
    end

    it "maps retirement-flavored investment subtypes to Retirement" do
      expect(described_class.map_account_type("investment", "roth ira")).to eq("Retirement")
    end

    it "maps other investment subtypes to Brokerage" do
      expect(described_class.map_account_type("investment", "brokerage")).to eq("Brokerage")
    end
  end

  describe "#display_name" do
    it "includes the masked number when a mask is present" do
      plaid_account = build(:plaid_account, name: "Checking", mask: "4242")
      expect(plaid_account.display_name).to eq("Checking (•••4242)")
    end

    it "returns just the name when mask is absent" do
      plaid_account = build(:plaid_account, name: "Savings", mask: nil)
      expect(plaid_account.display_name).to eq("Savings")
    end
  end
end
