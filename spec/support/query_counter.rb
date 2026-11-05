# Counts the SQL a block issues, so endpoint specs can pin query counts and
# catch N+1 regressions instead of only asserting the payload still looks
# right. A join that stops preloading, or a memoized resolver that stops
# memoizing, changes the count long before it changes the response body.
#
#   expect { get "/api/v1/portfolio", headers: h }.to issue_at_most(20).queries
#   count_queries { ... }.grep(/FROM "securities"/).size
module QueryCounter
  # Schema introspection and transaction bookkeeping are noise — the caller
  # cares about the queries the endpoint itself runs.
  IGNORED = /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|SET|SHOW)/i

  # Returns the SQL strings issued inside the block.
  def count_queries(&block)
    queries = []
    collector = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next if payload[:sql].match?(IGNORED)

      queries << payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(collector, "sql.active_record", &block)
    queries
  end
end

RSpec.configure { |config| config.include QueryCounter }

RSpec::Matchers.define :issue_at_most do |limit|
  # `.queries` reads naturally at the call site and is a no-op otherwise.
  def queries = self

  supports_block_expectations

  match do |block|
    @queries = QueryCounter.instance_method(:count_queries).bind(Object.new.extend(QueryCounter)).call(&block)
    @queries.size <= limit
  end

  failure_message do
    grouped = @queries.tally.sort_by { |_sql, n| -n }.first(5)
    breakdown = grouped.map { |sql, n| "  #{n}x #{sql[0, 120]}" }.join("\n")
    "expected at most #{limit} queries, got #{@queries.size}. Most repeated:\n#{breakdown}"
  end
end
