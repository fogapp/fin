require "rails_helper"

RSpec.describe Workflows::ActionExecutor do
  let(:merchant) { create(:merchant) }
  let(:txn)      { create(:cash_transaction, :credit_card, :sale) }

  def executor(dry_run: false)
    described_class.new(resource: txn, dry_run: dry_run)
  end

  describe "#execute" do
    it "runs the action and returns its result tagged with the action type" do
      result = executor.execute("assign_merchant", { "merchant_id" => merchant.id })
      expect(result).to include(status: :applied, action_type: "assign_merchant")
      expect(txn.reload.merchant_id).to eq(merchant.id)
    end

    it "returns :error for unknown action type" do
      result = executor.execute("nonexistent_action", {})
      expect(result).to include(status: :error, error: "Unknown action type: nonexistent_action")
    end

    it "returns :error instead of raising when the action blows up" do
      allow_any_instance_of(Workflows::Actions::AssignMerchant).to receive(:execute).and_raise("boom")
      result = executor.execute("assign_merchant", { "merchant_id" => merchant.id })
      expect(result).to include(status: :error, error: "boom")
    end

    it "does not persist changes in dry_run mode" do
      result = executor(dry_run: true).execute("assign_merchant", { "merchant_id" => merchant.id })
      expect(result[:status]).to eq(:applied)
      expect(txn.reload.merchant_id).to be_nil
    end

    # Step configs are stored JSON and the column actions write with
    # update_columns (no validations), so the action itself must refuse an id
    # from another household.
    it "refuses ids that belong to another household, writing nothing" do
      other = create(:household, name: "Other")
      foreign = Current.set(household: other) do
        { "assign_account" => [ "account_id", create(:account).id ],
          "assign_merchant" => [ "merchant_id", create(:merchant).id ],
          "assign_category" => [ "category_id", create(:category).id ],
          "set_loan" => [ "loan_id", create(:loan).id ],
          "add_tag" => [ "tag_id", create(:tag).id ] }
      end

      foreign.each do |action_type, (key, id)|
        result = executor.execute(action_type, { key => id })
        expect(result[:status]).to eq(:error), "#{action_type} should refuse a foreign #{key}"
      end
      txn.reload
      foreign_ids = foreign.values.map(&:last)
      expect(txn.attributes.values_at("account_id", "merchant_id", "category_id", "loan_id")).not_to include(*foreign_ids)
      expect(txn.tags).to be_empty
    end
  end
end
