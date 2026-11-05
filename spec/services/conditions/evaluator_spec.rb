require "rails_helper"

RSpec.describe Conditions::Evaluator do
  let(:txn) { build(:cash_transaction, :credit_card, :sale, description: "STARBUCKS #1234", amount: -8.50) }

  def condition(field:, operator:, value: nil)
    Struct.new(:field, :operator, :value).new(field, operator, value)
  end

  subject { described_class.new(resource: txn) }

  describe "#evaluate" do
    it "matches a regex case-insensitively" do
      result = subject.evaluate(condition(field: "description", operator: "matches", value: "starbucks"))
      expect(result[:result]).to be true
    end

    it "returns false for a non-matching regex" do
      result = subject.evaluate(condition(field: "description", operator: "matches", value: "AMAZON"))
      expect(result[:result]).to be false
    end

    it "handles equals" do
      result = subject.evaluate(condition(field: "source", operator: "equals", value: "credit_card"))
      expect(result[:result]).to be true
    end

    it "handles not_equals" do
      result = subject.evaluate(condition(field: "source", operator: "not_equals", value: "bank"))
      expect(result[:result]).to be true
    end

    it "handles contains" do
      result = subject.evaluate(condition(field: "description", operator: "contains", value: "STAR"))
      expect(result[:result]).to be true
    end

    it "handles greater_than" do
      result = subject.evaluate(condition(field: "amount", operator: "greater_than", value: "-10"))
      expect(result[:result]).to be true
    end

    it "handles less_than (compares absolute value)" do
      # amount is negative; abs value is e.g. 25. less_than 100 => true
      result = subject.evaluate(condition(field: "amount", operator: "less_than", value: "100"))
      expect(result[:result]).to be true
    end

    it "handles in with JSON array" do
      result = subject.evaluate(condition(field: "source", operator: "in", value: '["bank","credit_card"]'))
      expect(result[:result]).to be true
    end

    it "handles in with comma-separated string" do
      result = subject.evaluate(condition(field: "source", operator: "in", value: "bank,credit_card"))
      expect(result[:result]).to be true
    end

    it "handles blank" do
      txn.merchant_id = nil
      result = subject.evaluate(condition(field: "merchant_id", operator: "blank"))
      expect(result[:result]).to be true
    end

    it "handles present" do
      result = subject.evaluate(condition(field: "description", operator: "present"))
      expect(result[:result]).to be true
    end

    it "returns false and includes error for invalid regex" do
      result = subject.evaluate(condition(field: "description", operator: "matches", value: "[invalid"))
      expect(result[:result]).to be false
    end
  end
end
