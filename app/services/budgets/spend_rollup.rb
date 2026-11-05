# typed: strict

module Budgets
  # The budget "actual" rule, computed once for a span of months: a
  # category's spend in a month includes its subcategories' spend, except
  # subcategories that have their own budget line that month (their spend
  # belongs to that line instead). Transactions excluded from budgets
  # (one-off purchases) never count.
  #
  # Everything is sliced in memory from three window-wide loads — spend
  # grouped by month × category, the budgeted category ids per month (from
  # the caller's Budgets::Plan), and the category tree — so
  # Month, Calendar and Autofill share one definition and none of them issues
  # per-category queries.
  #
  # Summing the per-category month sums and taking abs at the end matches a
  # SQL SUM over the whole set exactly (BigDecimal addition).
  class SpendRollup
    extend T::Sig

    # [name, parent_id, budget_kind]
    CategoryRow = T.type_alias { [ String, T.nilable(String), T.untyped ] }

    sig { params(from: Date, to: Date, plan: Plan).void }
    def initialize(from:, to:, plan:)
      @from = T.let(from.beginning_of_month, Date)
      @to = T.let(to.end_of_month, Date)
      months = (0..((@to.year * 12 + @to.month) - (@from.year * 12 + @from.month))).map { |i| @from.months_since(i) }
      @budgeted_ids_by_month = T.let(plan.budgeted_ids_by_month(months), T::Hash[Date, T::Array[String]])
      @spend_by_month = T.let(nil, T.nilable(T::Hash[Date, T::Hash[T.nilable(String), T.untyped]]))
      @categories = T.let(nil, T.nilable(T::Hash[String, CategoryRow]))
      @children_by_parent = T.let(nil, T.nilable(T::Hash[T.nilable(String), T::Array[String]]))
    end

    # The category's budget actual for the month: its own spend plus its
    # children's, minus children budgeted on their own that month.
    sig { params(category_id: T.nilable(String), month: Date).returns(Float) }
    def spend(category_id, month)
      excluded = budgeted_ids(month) - [ category_id ]
      sum_for([ category_id ] + (children_of(category_id) - excluded), month)
    end

    # Spend with the children rolled in except `excluded` ones — used to
    # measure history by today's plan rather than the plan of the time.
    sig { params(category_id: T.nilable(String), month: Date, excluded: T::Array[String]).returns(Float) }
    def spend_excluding(category_id, month, excluded)
      sum_for([ category_id ] + (children_of(category_id) - excluded), month)
    end

    # Spend with every child rolled in regardless of their own lines — what
    # a child contributes when it rolls up into an unbudgeted-children view.
    sig { params(category_id: T.nilable(String), month: Date).returns(Float) }
    def spend_including_all_children(category_id, month)
      sum_for([ category_id ] + children_of(category_id), month)
    end

    # { category_id (or nil = uncategorized) => summed amount } for a month.
    sig { params(month: Date).returns(T::Hash[T.nilable(String), T.untyped]) }
    def sums(month)
      spend_by_month[month.beginning_of_month] || {}
    end

    # Category ids with any spend_like rows in the window.
    sig { returns(T::Array[String]) }
    def spent_category_ids
      spend_by_month.values.flat_map(&:keys).compact.uniq
    end

    # Up to `count` full months before `month`, newest first, skipping months
    # before the household's first spend — so a short history isn't padded
    # with zeros that drag a median down.
    sig { params(month: Date, count: Integer).returns(T::Array[Date]) }
    def history_months(month, count)
      first = first_spend_month
      return [] if first.nil?

      (1..count).map { |i| month.beginning_of_month.months_ago(i) }.select { |m| m >= first }
    end

    sig { params(month: Date).returns(T::Array[String]) }
    def budgeted_ids(month)
      @budgeted_ids_by_month[month.beginning_of_month] || []
    end

    sig { params(category_id: T.nilable(String)).returns(T::Array[String]) }
    def children_of(category_id)
      children_by_parent[category_id] || []
    end

    sig { params(category_id: String).returns(T.nilable(CategoryRow)) }
    def category(category_id)
      categories[category_id]
    end

    private

    sig { params(ids: T::Array[T.nilable(String)], month: Date).returns(Float) }
    def sum_for(ids, month)
      month_sums = sums(month)
      ids.sum { |id| month_sums[id] || 0 }.to_f.abs.round(2)
    end

    # { first-of-month => { category_id (or nil) => summed amount } } — one
    # grouped query over the window.
    sig { returns(T::Hash[Date, T::Hash[T.nilable(String), T.untyped]]) }
    def spend_by_month
      @spend_by_month ||= CashTransaction.spend_like
        .where(transaction_date: @from..@to, budget_excluded: false)
        .group(Arel.sql("(date_trunc('month', transaction_date))::date"), :category_id)
        .sum(:amount)
        .each_with_object({}) do |((month, category_id), amount), out|
          (out[month_key(month)] ||= {})[category_id] = amount
        end
    end

    sig { returns(T.nilable(Date)) }
    def first_spend_month
      return @first_spend_month if defined?(@first_spend_month)

      @first_spend_month = T.let(
        CashTransaction.spend_like.where(budget_excluded: false).minimum(:transaction_date)&.beginning_of_month,
        T.nilable(Date)
      )
    end

    sig { returns(T::Hash[String, CategoryRow]) }
    def categories
      @categories ||= Category.pluck(:id, :name, :parent_id, :budget_kind)
        .to_h { |(id, name, parent_id, kind)| [ id, [ name, parent_id, kind ] ] }
    end

    sig { returns(T::Hash[T.nilable(String), T::Array[String]]) }
    def children_by_parent
      @children_by_parent ||= categories.each_with_object({}) do |(id, (_name, parent_id, _kind)), out|
        (out[parent_id] ||= []) << id
      end
    end

    # Grouped calculation keys for computed expressions come back untyped on
    # some adapters — normalize to Date so hash lookups line up.
    sig { params(value: T.untyped).returns(Date) }
    def month_key(value)
      value.is_a?(Date) ? value : Date.parse(value.to_s)
    end
  end
end
