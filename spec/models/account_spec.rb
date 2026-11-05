require "rails_helper"

RSpec.describe Account, type: :model do
  describe "associations" do
    # broker presence is conditional (external accounts skip it), so the
    # matcher can't assert required/optional directly — the validations
    # block below covers both branches.
    it { is_expected.to belong_to(:broker).without_validating_presence }
    it { is_expected.to have_many(:investment_transactions).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:position_snapshots).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:cash_transactions).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:account_number) }

    it "scopes account_number uniqueness to broker" do
      broker = create(:broker)
      create(:account, broker: broker, account_number: "...1234")

      duplicate = build(:account, broker: broker, account_number: "...1234")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:account_number]).to include("has already been taken")
    end

    it "allows same account_number across different brokers" do
      create(:account, broker: create(:broker), account_number: "...1234")
      other = build(:account, broker: create(:broker), account_number: "...1234")

      expect(other).to be_valid
    end

    it "rejects an unknown kind" do
      account = build(:account, kind: "imaginary")
      expect(account).not_to be_valid
      expect(account.errors[:kind]).to be_present
    end

    it "requires a broker for standard accounts" do
      account = build(:account, broker: nil)
      expect(account).not_to be_valid
      expect(account.errors[:broker]).to be_present
    end
  end

  describe "external accounts" do
    it "can be created with just a name" do
      account = Account.new(name: "Schwab", kind: "external")
      expect(account).to be_valid
      account.save!

      expect(account.broker).to be_nil
      expect(account.account_number).to start_with("ext-")
      expect(account.balance).to be_nil
    end

    it "defaults kind to standard" do
      expect(create(:account).kind).to eq(Account::Kind::Standard)
    end

    it "keeps an explicitly provided account_number" do
      account = create(:account, kind: "external", broker: nil, account_number: "my-schwab")
      expect(account.account_number).to eq("my-schwab")
    end

    it "is excluded from net worth account breakdowns" do
      create(:account, kind: "external", broker: nil, account_number: nil, name: "Schwab")
      tracked = create(:account, balance: 100, balance_usd: 100)

      result = NetWorthHistory.new.call
      names = result[:accounts].map { |a| a[:name] }
      expect(names).to include(tracked.name)
      expect(names).not_to include("Schwab")
    end
  end

  describe "cash_transactions dependent: :nullify" do
    it "nullifies the account_id on associated cash transactions when destroyed" do
      account = create(:account)
      txn = create(:cash_transaction, :credit_card, account: account)

      account.destroy

      expect(txn.reload.account_id).to be_nil
    end
  end
end
