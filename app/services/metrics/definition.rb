# typed: strict

module Metrics
  # Base class for metric definitions — the code-side registry entries behind
  # the Stats system. A definition declares presentation metadata (label,
  # unit, direction, group) and knows how to compute its full series from raw
  # data for the current household. Computed values are persisted to
  # metric_points by Metrics::Backfill / Metrics::Refresh; the API reads only
  # the stored points.
  #
  # Contract:
  #   - series(from:, to:) returns { Date => Numeric | nil }, keyed by period
  #     start (first of month for :month granularity). nil means "undefined
  #     this period" (e.g. an average over zero transactions) and is stored
  #     as NULL. Always called inside Current.set(household:), so
  #     HouseholdScoped default scopes do the data scoping.
  #   - earliest_date returns the first date raw data exists (nil => no data).
  #   - breakdowns(from:, to:) optionally returns supporting tables for the
  #     detail endpoint, computed live (not persisted).
  class Definition
    extend T::Sig

    # Enum-typed DSL attributes and the enum class each one accepts.
    ENUM_ATTRS = T.let({
      unit:        Metrics::Unit,
      granularity: Metrics::Granularity,
      value_type:  Metrics::ValueType,
      direction:   Metrics::Direction,
      group:       Metrics::Group
    }.freeze, T::Hash[Symbol, T.class_of(T::Enum)])

    class << self
      extend T::Sig

      # Class-level DSL: `key :monthly_spend` sets, `key` reads. Values are
      # plain class ivars — no inheritance lookup needed since definitions
      # never subclass each other.
      %i[key label description].each do |attr|
        define_method(attr) do |value = :__read__|
          ivar = :"@#{attr}"
          instance_variable_set(ivar, value) unless value == :__read__
          instance_variable_get(ivar)
        end
      end

      # Same DSL shape for the enum-typed attributes, but only members of the
      # matching T::Enum are accepted — a stray symbol fails at class-load
      # time instead of leaking downstream.
      ENUM_ATTRS.each do |attr, enum_class|
        define_method(attr) do |value = :__read__|
          ivar = :"@#{attr}"
          unless value == :__read__
            raise ArgumentError, "#{attr} must be a #{enum_class.name}, got #{value.inspect}" unless value.is_a?(enum_class)

            instance_variable_set(ivar, value)
          end
          instance_variable_get(ivar)
        end
      end

      sig { params(route: T.nilable(String), params: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def drill(route: nil, params: {})
        @drill = T.let(@drill, T.nilable(T::Hash[Symbol, T.untyped]))
        @drill = { route: route, params: params } if route
        @drill
      end
    end

    sig { overridable.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
    def series(from:, to:)
      raise NotImplementedError, "#{self.class.name} must implement #series"
    end

    sig { overridable.returns(T.nilable(Date)) }
    def earliest_date
      raise NotImplementedError, "#{self.class.name} must implement #earliest_date"
    end

    # Detail-endpoint supporting tables:
    #   [{ label: "Top merchants", rows: [{ label:, value:, unit: }] }]
    sig { overridable.params(from: Date, to: Date).returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
    def breakdowns(from:, to:)
      nil
    end

    private

    # Grouped monthly sum with groupdate's range: option so months with no
    # rows materialize as 0 (continuous series). Keys normalized to Date.
    sig { params(scope: T.untyped, from: Date, to: Date, column: T.any(Symbol, String), date_column: Symbol, negate: T::Boolean).returns(T::Hash[Date, Float]) }
    def monthly_sum(scope, from:, to:, column: :amount, date_column: :transaction_date, negate: false)
      scope
        .group_by_period(:month, date_column, range: from..to)
        .sum(column)
        .to_h { |k, v| [ k.to_date, negate ? -v.to_f : v.to_f ] }
    end

    sig { params(scope: T.untyped, from: Date, to: Date, date_column: Symbol).returns(T::Hash[Date, Integer]) }
    def monthly_count(scope, from:, to:, date_column: :transaction_date)
      scope
        .group_by_period(:month, date_column, range: from..to)
        .count
        .to_h { |k, v| [ k.to_date, v.to_i ] }
    end
  end
end
