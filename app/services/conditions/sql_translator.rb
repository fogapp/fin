# typed: strict

module Conditions
  # Translates rule conditions into SQL WHERE clauses so Postgres does the
  # filtering instead of Ruby.  Returns [filtered_scope, untranslated_conditions]
  # where untranslated_conditions contains any conditions that couldn't be expressed
  # in SQL (e.g. referencing a virtual/delegated attribute).
  class SqlTranslator
    extend T::Sig

    # "matches" is deliberately NOT translatable: Postgres POSIX regexes and
    # Ruby's Onigmo differ in syntax, and an invalid pattern raises a SQL
    # error mid-statement while ConditionEvaluator rescues it to false. All
    # regex matching runs through the Ruby evaluator so every path agrees.
    # Derived structurally so a new Operator is translatable by default and
    # to_sql's exhaustive case forces a SQL form (or an explicit opt-out).
    TRANSLATABLE_OPS = T.let((Operator.values - [ Operator::Matches ]).freeze, T::Array[Operator])

    # Conditions are duck-typed (field/operator/value) — persisted
    # RuleCondition rows and the controllers' param structs both qualify.
    sig { params(conditions: T::Array[T.untyped], model_class: T.untyped, match_all: T::Boolean).void }
    def initialize(conditions, model_class, match_all:)
      @conditions = T.let(conditions, T::Array[T.untyped])
      @klass      = T.let(model_class, T.untyped)
      @match_all  = T.let(match_all, T::Boolean)
      @conn       = T.let(model_class.connection, T.untyped)
    end

    sig { params(scope: T.untyped).returns(T::Array[T.untyped]) }
    def apply(scope)
      translatable, ruby_conditions = @conditions.partition { |c| translatable?(c) }

      if translatable.any?
        frags = translatable.map { |c| to_sql(c) }.compact
        if @match_all
          # AND: chain individual WHERE clauses
          frags.each { |f| scope = scope.where(f) }
        else
          # OR: combine into a single WHERE (cond1) OR (cond2) ...
          scope = scope.where(frags.map { |f| "(#{f})" }.join(" OR "))
        end
      end

      [ scope, ruby_conditions ]
    end

    private

    sig { params(condition: T.untyped).returns(T.nilable(T::Boolean)) }
    def translatable?(condition)
      @klass.column_names.include?(condition.field.to_s) &&
        TRANSLATABLE_OPS.include?(Operator.try_deserialize(condition.operator.to_s))
    end

    sig { params(condition: T.untyped).returns(T.nilable(String)) }
    def to_sql(condition)
      operator = Operator.try_deserialize(condition.operator.to_s)
      return nil if operator.nil?

      col = @conn.quote_column_name(condition.field)
      val = condition.value.to_s

      case operator
      when Operator::Equals
        "#{col} = #{@conn.quote(val)}"
      when Operator::NotEquals
        # IS DISTINCT FROM so NULL rows count as "not equal", matching the
        # Ruby evaluator (nil.to_s != value).
        "#{col} IS DISTINCT FROM #{@conn.quote(val)}"
      when Operator::Contains
        # ILIKE for case-insensitive substring match
        "#{col} ILIKE #{@conn.quote("%#{sanitize_like(val)}%")}"
      when Operator::GreaterThan
        "ABS(#{col}::numeric) > #{val.to_f}"
      when Operator::LessThan
        "ABS(#{col}::numeric) < #{val.to_f}"
      when Operator::Blank
        "(#{col} IS NULL OR #{col} = '')"
      when Operator::Present
        "(#{col} IS NOT NULL AND #{col} != '')"
      when Operator::In
        list = parse_list(val)
        return "1=0" if list.empty? # empty IN () is a SQL syntax error

        quoted = list.map { |v| @conn.quote(v) }.join(", ")
        "#{col} IN (#{quoted})"
      when Operator::Matches
        nil # not translatable; translatable? keeps these on the Ruby path
      else
        T.absurd(operator)
      end
    end

    sig { params(value: String).returns(String) }
    def sanitize_like(value)
      value.gsub(/[%_\\]/) { |c| "\\#{c}" }
    end

    sig { params(value: String).returns(T::Array[String]) }
    def parse_list(value)
      JSON.parse(value)
    rescue JSON::ParserError
      value.split(",").map(&:strip)
    end
  end
end
