require "rails_helper"

# ConditionEvaluator (event path) and SqlTranslator (bulk path) implement the
# same operators twice. This matrix asserts they agree on every translatable
# operator over a shared fixture set, so the two paths can't silently drift —
# a rule preview and its bulk apply must always select the same rows.
RSpec.describe "Rules engine SQL/Ruby operator parity" do
  let!(:account) { create(:account) }

  let!(:fixtures) do
    [
      create(:cash_transaction, :bank, account: account, description: "STARBUCKS COFFEE",  amount: -5.00,  memo: nil),
      create(:cash_transaction, :bank, account: account, description: "starbucks reserve", amount: -20.50, memo: ""),
      create(:cash_transaction, :bank, account: account, description: "WALMART GROCERY",   amount: -100,   memo: "weekly run"),
      create(:cash_transaction, :bank, account: account, description: "Refund: Walmart",   amount: 42.13,  memo: "refund"),
      create(:cash_transaction, :bank, account: account, description: nil,                 amount: -7,     memo: nil)
    ]
  end

  CASES = [
    { field: "description", operator: "equals",       value: "STARBUCKS COFFEE" },
    { field: "description", operator: "not_equals",   value: "WALMART GROCERY" },
    { field: "description", operator: "contains",     value: "walmart" },
    { field: "description", operator: "contains",     value: "STARBUCKS" },
    { field: "description", operator: "blank",        value: "" },
    { field: "description", operator: "present",      value: "" },
    { field: "description", operator: "in",           value: "STARBUCKS COFFEE, WALMART GROCERY" },
    { field: "amount",      operator: "equals",       value: "5.00" },
    { field: "amount",      operator: "equals",       value: "-5" },
    { field: "amount",      operator: "greater_than", value: "10" },
    { field: "amount",      operator: "less_than",    value: "10" },
    { field: "memo",        operator: "blank",        value: "" },
    { field: "memo",        operator: "present",      value: "" },
    { field: "memo",        operator: "contains",     value: "REFUND" }
  ].freeze

  Condition = Struct.new(:field, :operator, :value)

  it "covers every translatable operator in the parity matrix" do
    # TRANSLATABLE_OPS is derived (Operator.values - [Matches]), so a newly
    # added operator is translatable by default — this guard forces it to
    # show up in CASES with a SQL/Ruby agreement check.
    expect(CASES.map { |c| c[:operator] }.uniq)
      .to match_array(Conditions::SqlTranslator::TRANSLATABLE_OPS.map(&:serialize))
  end

  CASES.each do |c|
    it "agrees on #{c[:field]} #{c[:operator]} #{c[:value].inspect}" do
      condition = Condition.new(c[:field], c[:operator], c[:value])

      sql_scope, leftover = Conditions::SqlTranslator
        .new([ condition ], CashTransaction, match_all: true)
        .apply(CashTransaction.all)
      expect(leftover).to be_empty, "expected #{c[:operator]} to be SQL-translatable"
      sql_ids = sql_scope.pluck(:id).sort

      ruby_ids = CashTransaction.all.select { |record|
        Conditions::Evaluator.new(resource: record).evaluate(condition)[:result]
      }.map(&:id).sort

      expect(sql_ids).to eq(ruby_ids),
        "SQL and Ruby disagree for #{c.inspect}:\n" \
        "  SQL-only:  #{CashTransaction.where(id: sql_ids - ruby_ids).pluck(:description)}\n" \
        "  Ruby-only: #{CashTransaction.where(id: ruby_ids - sql_ids).pluck(:description)}"
    end
  end

  it "routes the matches operator through Ruby everywhere (not translatable)" do
    condition = Condition.new("description", "matches", "^STAR")
    _scope, leftover = Conditions::SqlTranslator
      .new([ condition ], CashTransaction, match_all: true)
      .apply(CashTransaction.all)
    expect(leftover).to eq([ condition ])
  end

  describe "MatchQuery composition" do
    it "matches the pure-Ruby evaluation for mixed AND conditions" do
      conditions = [
        Condition.new("description", "contains", "starbucks"),          # SQL
        Condition.new("description", "matches", "RESERVE")              # Ruby
      ]

      relation_ids = Conditions::MatchQuery.new(
        resource_class: "CashTransaction", conditions: conditions, match_all: true
      ).relation.pluck(:id).sort

      ruby_ids = CashTransaction.all.select { |r|
        ev = Conditions::Evaluator.new(resource: r)
        conditions.all? { |c| ev.evaluate(c)[:result] }
      }.map(&:id).sort

      expect(relation_ids).to eq(ruby_ids)
      expect(relation_ids.size).to eq(1)
    end

    it "matches the pure-Ruby evaluation for mixed OR conditions" do
      conditions = [
        Condition.new("description", "contains", "walmart"),            # SQL
        Condition.new("description", "matches", "^STARBUCKS")           # Ruby
      ]

      relation_ids = Conditions::MatchQuery.new(
        resource_class: "CashTransaction", conditions: conditions, match_all: false
      ).relation.pluck(:id).sort

      ruby_ids = CashTransaction.all.select { |r|
        ev = Conditions::Evaluator.new(resource: r)
        conditions.any? { |c| ev.evaluate(c)[:result] }
      }.map(&:id).sort

      expect(relation_ids).to eq(ruby_ids)
      # walmart-contains rows (2) + IGNORECASE ^STARBUCKS rows (2)
      expect(relation_ids.size).to eq(4)
    end

    it "drops conditions for fields not in the registry" do
      query = Conditions::MatchQuery.new(
        resource_class: "CashTransaction",
        conditions:     [ Condition.new("destroy", "present", "") ],
        match_all:      true
      )
      expect(query.usable_conditions).to be_empty
    end
  end
end
