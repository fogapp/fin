# typed: true

# Metrics::Definition exposes its presentation metadata through class-level
# DSL macros (`key :net_worth`, `label "Net worth"`, `unit Unit::Currency`,
# ...) that are installed with `define_method` inside `class << self`, so
# Sorbet can't see them statically. Each macro is a reader when called with
# no argument and a writer when given one. This shim declares their static
# signatures; the runtime implementation lives in app/services/metrics/definition.rb.
module Metrics
  class Definition
    class << self
      sig { params(value: T.nilable(Symbol)).returns(T.nilable(Symbol)) }
      def key(value = nil); end

      sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
      def label(value = nil); end

      sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
      def description(value = nil); end

      sig { params(value: T.nilable(Metrics::Unit)).returns(T.nilable(Metrics::Unit)) }
      def unit(value = nil); end

      sig { params(value: T.nilable(Metrics::Granularity)).returns(T.nilable(Metrics::Granularity)) }
      def granularity(value = nil); end

      sig { params(value: T.nilable(Metrics::ValueType)).returns(T.nilable(Metrics::ValueType)) }
      def value_type(value = nil); end

      sig { params(value: T.nilable(Metrics::Direction)).returns(T.nilable(Metrics::Direction)) }
      def direction(value = nil); end

      sig { params(value: T.nilable(Metrics::Group)).returns(T.nilable(Metrics::Group)) }
      def group(value = nil); end
    end
  end
end
