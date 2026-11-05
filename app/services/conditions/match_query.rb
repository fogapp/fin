# typed: strict

module Conditions
  # The single entry point for "which records match these rule conditions".
  #
  # Translates the conditions it can into SQL (SqlTranslator) and evaluates
  # the rest in Ruby (ConditionEvaluator), composing the two correctly for
  # both AND and OR rules — for OR, the SQL pre-filter must not narrow what
  # the Ruby conditions get to see, so SQL-matched ids are unioned with a
  # Ruby pass over the remainder.
  #
  # Used by Api::V1::CashTransactionsController#filter (which backs both the
  # ad-hoc transaction filter and the rule-match preview UIs). Fields are
  # whitelisted against the Registry; conditions whose operator requires a
  # value but have a blank one are dropped.
  class MatchQuery < T::Struct
    extend T::Sig

    const :resource_class, String
    const :conditions, T.untyped
    const :match_all, T::Boolean
    const :base_scope, T.untyped, default: nil

    VALUE_OPTIONAL_OPS = T.let([ Operator::Blank, Operator::Present ].freeze, T::Array[Operator])

    # Conditions that will actually be evaluated. Exposed so callers can
    # distinguish "no usable conditions" (usually: render nothing / render
    # everything) from an empty result.
    sig { returns(T::Array[T.untyped]) }
    def usable_conditions
      @usable_conditions ||= T.let(conditions.to_a.select { |c| usable?(c) }, T.nilable(T::Array[T.untyped]))
    end

    # An ActiveRecord relation of matching records (unordered — callers add
    # includes/order/limit). With no usable conditions, returns the base scope.
    sig { returns(T.untyped) }
    def relation
      klass = resource_class.constantize
      scope = base_scope || klass.all
      conds = usable_conditions
      return scope if conds.empty?

      translated, ruby_conditions = SqlTranslator.new(conds, klass, match_all: match_all).apply(scope)
      return translated if ruby_conditions.empty?

      matching_ids = if match_all
        # The SQL-translated scope already satisfies the translatable
        # conditions; keep rows that also satisfy every Ruby condition.
        collect_ids(translated) { |ev| ruby_conditions.all? { |c| ev.evaluate(c)[:result] } }
      else
        # OR: union SQL-matched ids with rows matching any Ruby condition.
        sql_ids = ruby_conditions.size < conds.size ? translated.pluck(:id) : []
        sql_ids + collect_ids(scope.where.not(id: sql_ids)) { |ev|
          ruby_conditions.any? { |c| ev.evaluate(c)[:result] }
        }
      end

      klass.where(id: matching_ids)
    end

    private

    sig { params(condition: T.untyped).returns(T::Boolean) }
    def usable?(condition)
      field    = condition.field.to_s
      operator = Operator.try_deserialize(condition.operator.to_s)
      return false unless Registry.valid_field?(resource_class, field)
      return true if VALUE_OPTIONAL_OPS.include?(operator)

      condition.value.present?
    end

    sig { params(scope: T.untyped, block: T.untyped).returns(T::Array[T.untyped]) }
    def collect_ids(scope, &block)
      ids = []
      scope.find_each do |record|
        evaluator = Evaluator.new(resource: record)
        ids << record.id if yield(evaluator)
      end
      ids
    end
  end
end
