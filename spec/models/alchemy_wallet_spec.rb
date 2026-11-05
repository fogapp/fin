require "rails_helper"

RSpec.describe AlchemyWallet do
  describe "validations" do
    it "normalizes the address to lowercase" do
      wallet = create(:alchemy_wallet, address: "  0xAbC0000000000000000000000000000000006354 ")
      expect(wallet.address).to eq("0xabc0000000000000000000000000000000006354")
    end

    it "rejects malformed addresses" do
      expect(build(:alchemy_wallet, address: "abc123")).not_to be_valid
      expect(build(:alchemy_wallet, address: "0x123")).not_to be_valid
    end

    it "rejects duplicate addresses within a household" do
      existing = create(:alchemy_wallet)
      expect(build(:alchemy_wallet, address: existing.address.upcase)).not_to be_valid
    end

    it "rejects unsupported networks" do
      expect(build(:alchemy_wallet, networks: [ "eth-mainnet", "dogecoin" ])).not_to be_valid
      expect(build(:alchemy_wallet, networks: [])).not_to be_valid
    end
  end

  describe "#display_name" do
    it "falls back to the address suffix" do
      wallet = build(:alchemy_wallet, name: nil, address: "0xabc0000000000000000000000000000000006354")
      expect(wallet.display_name).to eq("Wallet 6354")
    end

    it "prefers the given name" do
      expect(build(:alchemy_wallet, name: "Main Vault").display_name).to eq("Main Vault")
    end
  end

  describe "#ensure_account!" do
    it "creates a Crypto account under the Self-Custody broker" do
      wallet  = create(:alchemy_wallet)
      account = wallet.ensure_account!

      expect(account.account_type).to eq("Crypto")
      expect(account.broker.name).to eq("Self-Custody")
      expect(account.account_number).to eq(wallet.address)
      expect(wallet.reload.account).to eq(account)
    end

    it "returns the existing account when already linked" do
      account = create(:account)
      wallet  = create(:alchemy_wallet, account: account)
      expect(wallet.ensure_account!).to eq(account)
    end

    it "relinks to an existing account with the same address" do
      wallet = create(:alchemy_wallet)
      original = wallet.ensure_account!
      wallet.update!(account: nil)

      expect(wallet.ensure_account!).to eq(original)
      expect(Account.where(account_number: wallet.address).count).to eq(1)
    end
  end
end
