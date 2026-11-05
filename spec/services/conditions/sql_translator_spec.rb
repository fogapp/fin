require "rails_helper"

RSpec.describe Conditions::SqlTranslator do
  Condition = Struct.new(:field, :operator, :value)

  def build_condition(field:, operator:, value: "")
    Condition.new(field, operator, value)
  end

  def translate(conditions, match_all: true, scope: CashTransaction.all)
    described_class.new(conditions, CashTransaction, match_all: match_all).apply(scope)
  end

  describe "#apply with AND (match_all)" do
    let(:account) { create(:account) }

    before do
      create(:cash_transaction, :bank, account: account, description: "STARBUCKS COFFEE",   amount: -5)
      create(:cash_transaction, :bank, account: account, description: "STARBUCKS RESERVE",  amount: -20)
      create(:cash_transaction, :bank, account: account, description: "WALMART GROCERY",    amount: -100)
    end

    it "filters with equals" do
      scope, leftover = translate([ build_condition(field: "description", operator: "equals", value: "STARBUCKS COFFEE") ])
      expect(scope.pluck(:description)).to eq([ "STARBUCKS COFFEE" ])
      expect(leftover).to be_empty
    end

    it "filters with contains (ILIKE, case-insensitive)" do
      scope, _ = translate([ build_condition(field: "description", operator: "contains", value: "starbucks") ])
      expect(scope.count).to eq(2)
    end

    it "escapes LIKE metacharacters in contains values" do
      create(:cash_transaction, :bank, account: account, description: "100% MATCH")
      scope, _ = translate([ build_condition(field: "description", operator: "contains", value: "100%") ])
      expect(scope.pluck(:description)).to eq([ "100% MATCH" ])
    end

    it "leaves matches (regex) untranslated for the Ruby evaluator" do
      # Postgres POSIX regexes and Ruby's Onigmo differ; regex matching is
      # deliberately routed through ConditionEvaluator on every path.
      condition = build_condition(field: "description", operator: "matches", value: "^STAR")
      scope, leftover = translate([ condition ])
      expect(leftover).to eq([ condition ])
      expect(scope.count).to eq(CashTransaction.count)
    end

    it "filters with greater_than on absolute amount" do
      scope, _ = translate([ build_condition(field: "amount", operator: "greater_than", value: "10") ])
      descs = scope.pluck(:description)
      expect(descs).to contain_exactly("STARBUCKS RESERVE", "WALMART GROCERY")
    end

    it "filters with less_than on absolute amount" do
      scope, _ = translate([ build_condition(field: "amount", operator: "less_than", value: "10") ])
      expect(scope.pluck(:description)).to eq([ "STARBUCKS COFFEE" ])
    end

    it "filters with not_equals" do
      scope, _ = translate([ build_condition(field: "description", operator: "not_equals", value: "WALMART GROCERY") ])
      expect(scope.count).to eq(2)
    end

    it "filters with in using JSON list" do
      scope, _ = translate([
        build_condition(field: "description", operator: "in",
                        value: %w[STARBUCKS\ COFFEE WALMART\ GROCERY].to_json)
      ])
      expect(scope.count).to eq(2)
    end

    it "filters with in using comma-separated list" do
      scope, _ = translate([
        build_condition(field: "description", operator: "in", value: "STARBUCKS COFFEE, WALMART GROCERY")
      ])
      expect(scope.count).to eq(2)
    end

    it "matches nothing (without a SQL error) for in with an empty list" do
      scope, _ = translate([ build_condition(field: "description", operator: "in", value: "[]") ])
      expect(scope.count).to eq(0)
    end

    it "filters with blank" do
      create(:cash_transaction, :bank, account: account, memo: "")
      create(:cash_transaction, :bank, account: account, memo: nil)
      create(:cash_transaction, :bank, account: account, memo: "set")

      scope, _ = translate([ build_condition(field: "memo", operator: "blank") ])
      expect(scope.where("memo IS NULL OR memo = ''").count).to eq(scope.count)
      expect(scope.count).to eq(5) # 3 originals (no memo set) + 2 new blanks
    end

    it "filters with present" do
      create(:cash_transaction, :bank, account: account, memo: "set")
      scope, _ = translate([ build_condition(field: "memo", operator: "present") ])
      expect(scope.count).to eq(1)
    end

    it "ANDs multiple translatable conditions" do
      scope, _ = translate([
        build_condition(field: "description", operator: "contains", value: "STARBUCKS"),
        build_condition(field: "amount",      operator: "greater_than", value: "10")
      ])
      expect(scope.pluck(:description)).to eq([ "STARBUCKS RESERVE" ])
    end
  end

  describe "#apply with OR (match_all: false)" do
    let(:account) { create(:account) }

    before do
      create(:cash_transaction, :bank, account: account, description: "STARBUCKS")
      create(:cash_transaction, :bank, account: account, description: "WALMART")
      create(:cash_transaction, :bank, account: account, description: "TARGET")
    end

    it "ORs multiple translatable conditions" do
      scope, _ = translate([
        build_condition(field: "description", operator: "equals", value: "STARBUCKS"),
        build_condition(field: "description", operator: "equals", value: "WALMART")
      ], match_all: false)

      expect(scope.pluck(:description)).to contain_exactly("STARBUCKS", "WALMART")
    end
  end

  describe "#apply with untranslatable conditions" do
    let(:account) { create(:account) }

    before do
      create(:cash_transaction, :bank, account: account, description: "STARBUCKS")
    end

    it "leaves the scope untouched and returns untranslatable conditions" do
      virtual = build_condition(field: "merchant_name", operator: "equals", value: "X")
      scope, leftover = translate([ virtual ])

      expect(scope.count).to eq(1)
      expect(leftover).to eq([ virtual ])
    end

    it "skips operators that aren't in the translatable list" do
      cond = build_condition(field: "description", operator: "starts_with", value: "STAR")
      scope, leftover = translate([ cond ])
      expect(scope.count).to eq(1)
      expect(leftover).to eq([ cond ])
    end

    it "partitions: translatable applied, untranslatable returned" do
      cond_t = build_condition(field: "description", operator: "equals", value: "STARBUCKS")
      cond_u = build_condition(field: "merchant_name", operator: "equals", value: "X")
      scope, leftover = translate([ cond_t, cond_u ])
      expect(scope.count).to eq(1)
      expect(leftover).to eq([ cond_u ])
    end
  end

  describe "#apply with no conditions" do
    it "returns the original scope unchanged" do
      scope, leftover = translate([])
      expect(scope.to_sql).to eq(CashTransaction.all.to_sql)
      expect(leftover).to be_empty
    end
  end
end
