# typed: strict

module Cashflow
  # Money-flow graph construction for the sankey chart: income sources →
  # Income hub → spending buckets (+ Savings when income exceeds spend).
  # Nodes carry drill metadata so the chart can navigate to filtered
  # transactions; the folded "Other" nodes carry their rows as `members` so
  # the chart can expand them in place.
  class SankeyGraph
    extend T::Sig

    TOP_SOURCES    = 6
    TOP_CATEGORIES = 8

    # One graph for a pair of scopes — the endpoint calls it once with
    # everything and once with outlier spend excluded. `dimension` picks
    # what the spend side fans out into (categories, parent-category
    # groups, or merchants).
    sig { params(income_scope: T.untyped, spend_scope: T.untyped, dimension: String).returns(T::Hash[Symbol, T.untyped]) }
    def self.call(income_scope:, spend_scope:, dimension:)
      sources = income_scope
        .joins("LEFT JOIN merchants ON merchants.id = cash_transactions.merchant_id")
        .group("COALESCE(merchants.name, cash_transactions.description)", "merchants.id")
        .sum(:amount)
        .map { |(name, merchant_id), amount| { name: name, merchant_id: merchant_id, value: amount.to_f.round(2) } }
        .sort_by { |row| -row[:value] }
      sources = fold_tail(sources, TOP_SOURCES, name: "Other income")

      categories = spend_buckets(spend_scope, dimension)
        .select { |row| row[:value].positive? }
        .sort_by { |row| -row[:value] }
      categories = fold_tail(categories, TOP_CATEGORIES, name: "Other spending")

      income_total = sources.sum { |row| row[:value] }.round(2)
      spend_total  = categories.sum { |row| row[:value] }.round(2)
      savings      = (income_total - spend_total).round(2)

      # Annotated: the node kinds carry different id keys, so inferring the
      # array type from the first `map` makes every later push a shape error.
      nodes = T.let(
        sources.map { |row| { name: row[:name], kind: "income_source", **row.slice(:merchant_id, :members) } },
        T::Array[T::Hash[Symbol, T.untyped]]
      )
      # When spend outruns income, the gap feeds the hub as its own source.
      # Without it the hub would be sized (and labeled) by its outflow, so an
      # "Income" node would show the spend total rather than income.
      shortfall = savings.negative? ? -savings : 0.0
      if shortfall.positive?
        sources += [ { name: "From savings", value: shortfall } ]
        nodes << { name: "From savings", kind: "shortfall" }
      end
      nodes << { name: shortfall.positive? ? "Income + savings" : "Income", kind: "hub" }
      nodes += categories.map do |row|
        { name: row[:name], kind: "category", **row.slice(:category_id, :category_ids, :merchant_id, :members) }
      end
      nodes << { name: "Savings", kind: "savings" } if savings.positive?

      hub = sources.size
      links = sources.each_with_index.map { |row, i| { source: i, target: hub, value: row[:value] } }
      links += categories.each_with_index.map { |row, i| { source: hub, target: hub + 1 + i, value: row[:value] } }
      links << { source: hub, target: nodes.size - 1, value: savings } if savings.positive?

      {
        totals: { income: income_total, spend: spend_total, savings: savings },
        nodes: nodes, links: links.reject { |l| l[:value] <= 0 }
      }
    end

    # Spend rows for one sankey dimension: `{name, value, <drill key>}`.
    # Values are negated (not abs'd) so refunds net out; drill keys are what
    # the frontend turns into a transaction filter — `category_id` for a
    # category, `category_ids` (parent + children) for a group, and
    # `merchant_id` for a merchant. Buckets that aggregate rows with no
    # drillable identity (Uncategorized, No merchant) carry no key.
    sig { params(spend_scope: T.untyped, dimension: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.spend_buckets(spend_scope, dimension)
      case dimension
      when "merchant"
        spend_scope
          .joins("LEFT JOIN merchants ON merchants.id = cash_transactions.merchant_id")
          .group("COALESCE(merchants.name, 'No merchant')", "merchants.id")
          .sum(:amount)
          .map do |(name, merchant_id), amount|
            row = { name: name, value: (-amount.to_f).round(2) }
            merchant_id ? row.merge(merchant_id: merchant_id) : row
          end
      when "category_group"
        rows = spend_scope
          .joins("LEFT JOIN categories ON categories.id = cash_transactions.category_id")
          .joins("LEFT JOIN categories parent_categories ON parent_categories.id = categories.parent_id")
          .group(
            Arel.sql("COALESCE(parent_categories.name, categories.name, 'Uncategorized')"),
            Arel.sql("COALESCE(parent_categories.id, categories.id)")
          )
          .sum(:amount)
          .map { |(name, group_id), amount| { name: name, group_id: group_id, value: (-amount.to_f).round(2) } }
        children = ::Category.where(parent_id: rows.filter_map { |r| r[:group_id] })
          .pluck(:parent_id, :id)
          .group_by(&:first)
          .transform_values { |pairs| pairs.map(&:last) }
        rows.map do |row|
          drill = row[:group_id] ? { category_ids: [ row[:group_id], *children[row[:group_id]] ] } : {}
          { name: row[:name], value: row[:value], **drill }
        end
      else
        spend_scope
          .joins("LEFT JOIN categories ON categories.id = cash_transactions.category_id")
          .group("COALESCE(categories.name, 'Uncategorized')", "categories.id")
          .sum(:amount)
          .map { |(name, category_id), amount| { name: name, category_id: category_id, value: (-amount.to_f).round(2) } }
      end
    end
    private_class_method :spend_buckets

    sig { params(rows: T::Array[T::Hash[Symbol, T.untyped]], keep: Integer, name: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.fold_tail(rows, keep, name:)
      return rows if rows.size <= keep

      head = rows.first(keep)
      tail_value = rows.drop(keep).sum { |row| row[:value] }.round(2)
      head + [ { name: name, value: tail_value, members: rows.drop(keep) } ]
    end
    private_class_method :fold_tail
  end
end
