require "rails_helper"

RSpec.describe Merchants::RuleMatcher do
  describe ".match" do
    it "returns nil for blank descriptions" do
      expect(described_class.match(nil)).to be_nil
      expect(described_class.match("")).to be_nil
    end

    it "matches a description against a rule's pattern" do
      starbucks = create(:merchant, name: "Starbucks")
      create(:merchant_rule, merchant: starbucks, pattern: "STARBUCKS")

      expect(described_class.match("STARBUCKS #1234")).to eq(starbucks)
    end

    it "is case-insensitive" do
      m = create(:merchant, name: "Amazon")
      create(:merchant_rule, merchant: m, pattern: "amazon")

      expect(described_class.match("AMAZON.COM*ABC")).to eq(m)
    end

    it "honours rule priority (higher priority wins)" do
      generic = create(:merchant, name: "Generic Coffee")
      branded = create(:merchant, name: "Starbucks")
      create(:merchant_rule, merchant: generic, pattern: "COFFEE", priority: 0)
      create(:merchant_rule, merchant: branded, pattern: "STARBUCKS", priority: 10)

      expect(described_class.match("STARBUCKS COFFEE #1")).to eq(branded)
    end

    it "returns nil when no rule matches" do
      m = create(:merchant)
      create(:merchant_rule, merchant: m, pattern: "STARBUCKS")

      expect(described_class.match("UNKNOWN VENDOR")).to be_nil
    end

    it "silently skips rules with invalid regexes via filter_map" do
      good = create(:merchant, name: "Good")
      create(:merchant_rule, merchant: good, pattern: "GOOD")
      bad = create(:merchant, name: "Bad")
      MerchantRule.new(merchant: bad, pattern: "[invalid").save(validate: false)

      expect(described_class.match("GOOD STUFF")).to eq(good)
    end
  end

  describe ".match_result" do
    it "returns the rule's category when set" do
      m = create(:merchant, category: create(:category, name: "Default"))
      override_cat = create(:category, name: "Coffee")
      create(:merchant_rule, merchant: m, pattern: "STARBUCKS", category: override_cat)

      result = described_class.match_result("STARBUCKS #1")
      expect(result.merchant).to eq(m)
      expect(result.category).to eq(override_cat)
    end

    it "falls back to merchant's category when rule has none" do
      cat = create(:category, name: "Default")
      m = create(:merchant, category: cat)
      create(:merchant_rule, merchant: m, pattern: "STARBUCKS")

      result = described_class.match_result("STARBUCKS #1")
      expect(result.category).to eq(cat)
    end
  end

  describe ".rematch_all" do
    it "bumps the household data version once so cached endpoints rotate" do
      sbux = create(:merchant, name: "Starbucks")
      create(:merchant_rule, merchant: sbux, pattern: "STARBUCKS")
      create(:cash_transaction, :credit_card, :sale, description: "STARBUCKS #1234")

      # update_all skips callbacks — the explicit bump is the only rotation.
      expect(Households::DataVersion).to receive(:bump!).with(Current.household.id).once
      described_class.rematch_all
    end

    it "matches and updates merchant_id and category_id, counting matches" do
      coffee_cat = create(:category, name: "Coffee")
      sbux = create(:merchant, name: "Starbucks", category: coffee_cat)
      create(:merchant_rule, merchant: sbux, pattern: "STARBUCKS")

      txn   = create(:cash_transaction, :credit_card, :sale, description: "STARBUCKS #1234")
      other = create(:cash_transaction, :credit_card, :sale, description: "UNKNOWN VENDOR")

      result = described_class.rematch_all

      expect(txn.reload.merchant).to eq(sbux)
      expect(txn.category).to eq(coffee_cat)
      expect(other.reload.merchant).to be_nil
      expect(result[:matched]).to be >= 1
      expect(result[:unmatched]).to be >= 1
    end

    it "matches bank-sourced transactions too" do
      sbux = create(:merchant, name: "Starbucks")
      create(:merchant_rule, merchant: sbux, pattern: "STARBUCKS")

      txn = create(:cash_transaction, :bank, description: "STARBUCKS #1234")

      described_class.rematch_all

      expect(txn.reload.merchant).to eq(sbux)
    end

    it "matches cash transactions" do
      sbux = create(:merchant, name: "Starbucks")
      create(:merchant_rule, merchant: sbux, pattern: "STARBUCKS")

      txn = create(:cash_transaction, :credit_card, :sale, description: "STARBUCKS #1234")

      described_class.rematch_all

      expect(txn.reload.merchant).to eq(sbux)
    end

    it "uses raw_category as a fallback for unmatched cash transactions" do
      create(:category, name: "Dining")
      txn = create(:cash_transaction, :credit_card, :sale, description: "UNKNOWN CAFE", raw_category: "Dining")

      described_class.rematch_all

      expect(txn.reload.category.name).to eq("Dining")
      expect(txn.merchant).to be_nil
    end

    it "preserves existing assignments when a transaction matches no rule" do
      # No provenance flag distinguishes rule-made from manual assignments, so
      # rematch_all must never null out rows it has no rule outcome for —
      # wiping manual categorization is worse than keeping a stale rule match.
      sbux = create(:merchant, name: "Starbucks")
      txn = create(:cash_transaction, :credit_card, :sale, description: "STARBUCKS #1", merchant: sbux)

      described_class.rematch_all

      expect(txn.reload.merchant).to eq(sbux)
    end

    it "does not overwrite an existing category with the raw_category fallback" do
      dining = create(:category, name: "Dining")
      manual = create(:category, name: "Coffee Budget")
      txn = create(:cash_transaction, :credit_card, :sale,
                   description: "UNKNOWN CAFE", raw_category: "Dining", category: manual)

      described_class.rematch_all

      expect(txn.reload.category).to eq(manual)
    end
  end
end
