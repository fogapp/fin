# typed: strict

module Conditions
  # The condition-operator vocabulary shared by rules and workflow steps.
  # Stored rule/workflow config JSON persists the serialized strings, so
  # deserialize at the evaluation boundary (ConditionEvaluator/SqlTranslator)
  # and keep storage and API payloads as plain strings.
  class Operator < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Matches = new("matches")
      Equals = new("equals")
      NotEquals = new("not_equals")
      Contains = new("contains")
      GreaterThan = new("greater_than")
      LessThan = new("less_than")
      In = new("in")
      Blank = new("blank")
      Present = new("present")
    end
  end
end
