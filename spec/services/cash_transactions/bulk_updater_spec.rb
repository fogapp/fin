require "rails_helper"

RSpec.describe CashTransactions::BulkUpdater do
  def call(ids:, **opts)
    described_class.new(ids: ids, **opts).call
  end

  it "raises ArgumentError when ids is empty" do
    expect { call(ids: []) }.to raise_error(ArgumentError, "ids is required")
  end

  describe "account assignment" do
    it "sets account_id on all specified transactions" do
      account = create(:account)
      t1 = create(:cash_transaction, :credit_card, :sale)
      t2 = create(:cash_transaction, :credit_card, :sale)

      result = call(ids: [ t1.id, t2.id ], account_id: account.id)

      expect(t1.reload.account_id).to eq(account.id)
      expect(t2.reload.account_id).to eq(account.id)
      expect(result.account_id).to eq(account.id)
      expect(result.updated).to eq(2)
    end

    it "raises RecordNotFound for a nonexistent account" do
      t = create(:cash_transaction, :credit_card, :sale)
      expect { call(ids: [ t.id ], account_id: "00000000-0000-0000-0000-000000000000") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "skips account assignment when account_id is blank" do
      t = create(:cash_transaction, :credit_card, :sale)
      result = call(ids: [ t.id ])
      expect(result.account_id).to be_nil
      expect(t.reload.account_id).to be_nil
    end
  end

  describe "tag assignment" do
    it "adds tags to all specified transactions" do
      tag1 = create(:tag)
      tag2 = create(:tag)
      t1   = create(:cash_transaction, :credit_card, :sale)
      t2   = create(:cash_transaction, :credit_card, :sale)

      result = call(ids: [ t1.id, t2.id ], tag_ids: [ tag1.id, tag2.id ])

      expect(t1.reload.tags).to match_array([ tag1, tag2 ])
      expect(t2.reload.tags).to match_array([ tag1, tag2 ])
      expect(result.tag_ids).to match_array([ tag1.id, tag2.id ])
    end

    it "does not duplicate tags already on a transaction" do
      tag = create(:tag)
      t   = create(:cash_transaction, :credit_card, :sale)
      t.tags << tag

      expect { call(ids: [ t.id ], tag_ids: [ tag.id ]) }
        .not_to change { t.reload.tags.count }
    end

    it "skips tag assignment when tag_ids is blank" do
      t = create(:cash_transaction, :credit_card, :sale)
      result = call(ids: [ t.id ])
      expect(result.tag_ids).to be_empty
    end
  end

  describe "counting" do
    let(:missing_id) { "00000000-0000-0000-0000-000000000000" }

    it "reports only transactions that actually exist" do
      t = create(:cash_transaction, :credit_card, :sale)
      account = create(:account)

      result = call(ids: [ t.id, missing_id ], account_id: account.id)

      expect(result.updated).to eq(1)
    end

    it "skips nonexistent ids when inserting tags instead of violating the FK" do
      tag = create(:tag)
      t   = create(:cash_transaction, :credit_card, :sale)

      result = call(ids: [ t.id, missing_id ], tag_ids: [ tag.id ])

      expect(result.updated).to eq(1)
      expect(t.reload.tags).to eq([ tag ])
    end
  end

  it "can set account and tags in one call" do
    account = create(:account)
    tag     = create(:tag)
    t       = create(:cash_transaction, :credit_card, :sale)

    result = call(ids: [ t.id ], account_id: account.id, tag_ids: [ tag.id ])

    expect(t.reload.account_id).to eq(account.id)
    expect(t.reload.tags).to include(tag)
    expect(result.account_id).to eq(account.id)
    expect(result.tag_ids).to include(tag.id)
  end
end
