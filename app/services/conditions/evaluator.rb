# typed: strict

module Conditions
  class Evaluator < T::Struct
    const :resource, T.untyped


    sig { params(condition: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def evaluate(condition)
      field_value = compute_field(condition.field)
      # Operators arrive as strings from stored rule/workflow config; an
      # unknown one evaluates to false, matching the old else branch.
      operator    = Operator.try_deserialize(condition.operator.to_s)
      result      = operator.nil? ? false : apply_operator(operator, field_value, condition.value)
      { field: condition.field, operator: condition.operator, value: condition.value,
        actual: field_value.to_s, result: result }
    rescue => e
      { field: condition.field, operator: condition.operator, value: condition.value,
        actual: nil, result: false, error: e.message }
    end

    private

    COMPUTED_FIELDS = T.let(%w[transfer_counterpart_count].freeze, T::Array[String])

    sig { params(field: String).returns(T.untyped) }
    def compute_field(field)
      case field
      when "transfer_counterpart_count"
        transfer_counterpart_count
      else
        resource.public_send(field)
      end
    end

    sig { returns(Integer) }
    def transfer_counterpart_count
      return 0 unless resource.is_a?(CashTransaction)
      return 0 if resource.transfer_id.present?

      tolerance = Transfer::AMOUNT_TOLERANCE
      days      = Transfer::CANDIDATE_DAYS

      CashTransaction
        .where.not(id: resource.id)
        .where.not(account_id: resource.account_id)
        .where(transfer_id: nil)
        .where("ABS(amount + ?) < ?", resource.amount, tolerance)
        .where("ABS(transaction_date::date - ?::date) <= ?", resource.transaction_date, days)
        .count
    end

    # Operator semantics here are the canonical ones; SqlTranslator's SQL
    # forms must agree (see spec/services/conditions/parity_spec.rb):
    # - contains is case-insensitive, like the SQL path's ILIKE
    # - equals/not_equals compare numerically when the field is numeric,
    #   like Postgres comparing a numeric column against a quoted literal
    #   ("5" == "5.00" for an amount, but not for a description)
    sig { params(operator: Operator, field_value: T.untyped, value: T.untyped).returns(T::Boolean) }
    def apply_operator(operator, field_value, value)
      case operator
      when Operator::Matches     then field_value.to_s.match?(Regexp.new(value.to_s, Regexp::IGNORECASE))
      when Operator::Equals      then values_equal?(field_value, value)
      when Operator::NotEquals   then !values_equal?(field_value, value)
      when Operator::Contains    then field_value.to_s.downcase.include?(value.to_s.downcase)
      when Operator::GreaterThan then field_value.to_f.abs > value.to_f
      when Operator::LessThan    then field_value.to_f.abs < value.to_f
      when Operator::In          then parse_list(value).include?(field_value.to_s)
      when Operator::Blank       then field_value.blank?
      when Operator::Present     then field_value.present?
      else T.absurd(operator)
      end
    rescue RegexpError
      false
    end

    sig { params(field_value: T.untyped, value: T.untyped).returns(T::Boolean) }
    def values_equal?(field_value, value)
      if field_value.is_a?(Numeric)
        decimal = begin
          BigDecimal(value.to_s)
        rescue ArgumentError
          nil
        end
        return BigDecimal(field_value.to_s) == decimal unless decimal.nil?
      end
      field_value.to_s == value.to_s
    end

    sig { params(value: T.untyped).returns(T::Array[String]) }
    def parse_list(value)
      JSON.parse(value.to_s)
    rescue JSON::ParserError
      value.to_s.split(",").map(&:strip)
    end
  end
end
