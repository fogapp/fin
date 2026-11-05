# typed: strict

# Grouped-timeline pagination shared by the activity feed and workflow runs
# list: both collapse rows into one entry per causal episode (a trace), and
# both need the page of group keys computed inside the grouped query —
# plucking every key into Ruby made those paths effectively unpaginated.
#
# The caller supplies what actually differs between the two feeds: the
# group-key expression(s) and the timestamp column. Each page-key row comes
# back as the key column(s) followed by COUNT(*), MIN(timestamp), and
# MAX(timestamp) for the group, ordered by most-recent activity first.
class TraceGrouping
  extend T::Sig

  PER_PAGE = 30

  class Result < T::Struct
    const :page_keys, T::Array[T.untyped]
    const :total, Integer
  end

  sig do
    params(
      scope:     ActiveRecord::Relation,
      key:       T.any(T::Array[Symbol], Arel::Nodes::SqlLiteral),
      timestamp: Symbol,
      per_page:  Integer
    ).void
  end
  def initialize(scope:, key:, timestamp:, per_page: PER_PAGE)
    # Order can't survive under GROUP BY, and includes would drag eager
    # loads into a pure aggregate query.
    @scope = T.let(scope.unscope(:order, :includes), ActiveRecord::Relation)
    @key = T.let(Array(key), T::Array[T.any(Symbol, Arel::Nodes::SqlLiteral)])
    @timestamp = timestamp
    @per_page = per_page
  end

  sig { params(page: Integer).returns(Result) }
  def page(page)
    total = @scope.distinct.count(count_expression)
    timestamp = @scope.klass.arel_table[@timestamp]
    page_keys = @scope
      .group(*@key)
      .order(timestamp.maximum.desc)
      .offset((page - 1) * @per_page)
      .limit(@per_page)
      .pluck(*@key, Arel.star.count, timestamp.minimum, timestamp.maximum)
    Result.new(page_keys: page_keys, total: total)
  end

  sig { returns(Integer) }
  def per_page = @per_page

  private

  # COUNT(DISTINCT (a, b, c)) — the row-expression tuple — is valid
  # Postgres; the multi-argument COUNT(DISTINCT a, b, c) form is not.
  sig { returns(T.any(Symbol, Arel::Nodes::SqlLiteral, Arel::Nodes::Grouping)) }
  def count_expression
    return T.must(@key.first) if @key.length == 1

    table = @scope.klass.arel_table
    Arel::Nodes::Grouping.new(@key.map { |k| k.is_a?(Symbol) ? table[k] : k })
  end
end
