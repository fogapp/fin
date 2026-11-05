# typed: strict

module Workflows
  # Shared condition evaluation for branch steps and monitors: the
  # parity-tested rules evaluator plus the catalog field whitelist, so
  # stored configs can never public_send arbitrary methods on a subject.
  module ConditionCheck
    extend T::Sig

    sig { params(subject: T.untyped, conditions: T::Array[T.untyped], match_all: T::Boolean).returns(T::Boolean) }
    def self.match?(subject, conditions, match_all: true)
      return false if subject.nil?

      evaluator = Conditions::Evaluator.new(resource: subject)
      results = conditions.map do |condition|
        next false unless Catalog.valid_field?(subject.class.name, condition.field.to_s)

        evaluator.evaluate(condition)[:result]
      end

      match_all ? results.all? : results.any?
    end
  end
end
