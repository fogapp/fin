# typed: strict

module Api
  module Render
    class CashTransaction < Api::Render::Base
      extend T::Sig

      include Api::Render::Concerns::SerializesTransactionRow

      # Server-side ceiling: the transaction page streams pages of 1,000
      # (frontend useAllTransactions PAGE_SIZE), so an omitted limit serves
      # exactly one such page instead of the entire table.
      MAX_LIMIT = 1_000

      # Rule-condition previews (#filter): loose conditions can match the
      # whole table, so an omitted limit serves a bounded sample.
      FILTER_DEFAULT_LIMIT = 100
      FILTER_MAX_LIMIT     = 1_000

      # Every association #serialize reads — index, show and filter all
      # preload exactly this, so no row lazy-loads its category parent,
      # transfer or loan.
      ROW_INCLUDES = T.let(
        [ :merchant, { category: :parent }, :account, :tags, :loan, :transfer ].freeze,
        T::Array[T.untyped]
      )

      # "Have I seen this charge before?" — how many rows the pane shows, and
      # how alike two descriptions have to be to count.
      SIMILAR_LIMIT = 8
      SIMILAR_MAX_LIMIT = 50

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        # All param→scope semantics (including the category_id rollup and the
        # from/to aliases for start_date/end_date) live in the shared filter.
        scope = ::CashTransactions::Filter.new(params).relation(::CashTransaction.all)

        # id tiebreaker keeps the order stable across limit/offset pages —
        # same-date rows would otherwise shuffle between page fetches.
        scope = scope.order(transaction_date: :desc, id: :desc).includes(*ROW_INCLUDES)

        # Windowing — the shape stays a bare array for compatibility; clients
        # page with limit/offset, and an omitted limit falls back to MAX_LIMIT
        # so the endpoint can never serialize the whole table in one response.
        limit, offset = Paginated.window(params, default: MAX_LIMIT, max: MAX_LIMIT)
        scope.offset(offset).limit(limit).map { |t| serialize(t) }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        serialize(::CashTransaction.includes(*ROW_INCLUDES).find(params[:id]))
      end

      # Transactions matching an ad-hoc condition set — the workflow editor's
      # condition preview. `count` adds the full match count alongside the
      # (bounded) sample.
      sig { returns(T.any(T::Array[T::Hash[Symbol, T.untyped]], T::Hash[Symbol, T.untyped])) }
      def filter
        match_all = ActiveModel::Type::Boolean.new.cast(params.fetch(:match_all, true))
        query     = ::Conditions::MatchQuery.new(
          resource_class: "CashTransaction",
          conditions:     condition_structs(Array(params[:conditions])),
          match_all:      match_all
        )

        limit, = Paginated.window(params, default: FILTER_DEFAULT_LIMIT, max: FILTER_MAX_LIMIT)
        rows = query.relation
          .includes(*ROW_INCLUDES)
          .order(transaction_date: :desc)
          .limit(limit)
          .map { |t| serialize(t) }

        params[:count].present? ? { transactions: rows, total: query.relation.count } : rows
      end

      # Unlinked transactions near the given one, for manual transfer
      # pairing. Bounded window (±days, capped) keeps the picker relevant
      # and the query cheap.
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def transfer_search
        source = ::CashTransaction.find(params.require(:transaction_id))
        days   = params[:days].present? ? params[:days].to_i.clamp(1, 30) : 14
        from_d = source.transaction_date - days.days
        to_d   = source.transaction_date + days.days
        target = -source.amount

        # Candidates for "the other side of this transfer": money moving the
        # opposite way in a different account, ranked so an exact amount sorts
        # first and, among equal amounts, the nearest date. The old form
        # returned every unlinked row in the window in date order, and a busy
        # month overflowed the cap before the counterpart ever appeared.
        scope = ::CashTransaction
          .includes(:account)
          .where(transaction_date: from_d..to_d)
          .where.not(id: source.id)
          .where(transfer_id: nil)
          .where(source.amount.negative? ? "amount > 0" : "amount < 0")
        scope = scope.where.not(account_id: source.account_id) if source.account_id

        scope
          .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([
            "ABS(cash_transactions.amount - ?) ASC, ABS(cash_transactions.transaction_date - DATE ?) ASC",
            target, source.transaction_date
          ])), :id)
          .limit(100)
          .map do |t|
            transaction_row(t).merge(
              amount_diff: (t.amount - target).abs.to_f.round(2),
              date_diff:   (t.transaction_date - source.transaction_date).abs.to_i
            )
          end
      end

      # Other transactions carrying the same — or nearly the same —
      # description as this one, newest first, so the pane can answer "have I
      # paid this before, and how much?".
      #
      # Matching is on the raw descriptor via pg_trgm, which is case- and
      # noise-tolerant: "SQ *CAFE 0042" and "SQ *CAFE 0117" score ~0.8 and
      # both land. An identical description scores 1.0, so exact matches need
      # no separate clause — they simply sort first.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def similar
        source = ::CashTransaction.find(params[:id])
        query  = source.description.to_s.strip
        return { transactions: [], total: 0, total_amount: 0.0 } if query.blank?

        scope = ::CashTransactions::Context.similar_scope(source, query)
        limit = params[:limit].present? ? params[:limit].to_i.clamp(1, SIMILAR_MAX_LIMIT) : SIMILAR_LIMIT

        rows = scope
          .includes(:account)
          .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([
            "similarity(cash_transactions.description, ?) DESC", query
          ])), transaction_date: :desc)
          .limit(limit)
          .map { |t| transaction_row(t).merge(match: t.description.to_s.strip.casecmp?(query) ? "exact" : "similar") }

        # Totals cover every match, not just the rows above — the pane reports
        # "12 similar · $431 total" over the whole history.
        { transactions: rows, total: scope.count, total_amount: scope.sum(:amount).to_f }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def context
        ::CashTransactions::Context.new(::CashTransaction.includes(:merchant, :category).find(params[:id])).call
      end

      sig { params(t: ::CashTransaction).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(t)
        {
          id:               t.id,
          source:           t.source,
          transaction_date: t.transaction_date,
          post_date:        t.post_date,
          description:      t.description,
          amount:           t.amount.to_f,
          transaction_type: t.transaction_type,
          category_id:      t.category_id,
          category_name:    t.category&.name,
          # Subcategory names aren't unique across parents (Car › Gas vs
          # Home › Gas), so anything grouping by category needs this too.
          category_parent_name: t.category&.parent&.name,
          merchant_id:      t.merchant_id,
          merchant_name:    t.merchant&.name,
          account_id:       t.account_id,
          account_name:     t.account&.name,
          balance:          t.balance&.to_f,
          memo:             t.memo,
          transfer_id:      t.transfer_id,
          transfer_kind:    t.transfer&.kind,
          transfer_include_in_spend: t.transfer&.include_in_spend,
          loan_id:          t.loan_id,
          loan_name:        t.loan&.name,
          budget_excluded:  t.budget_excluded,
          tags:             t.tags.map { |tag| { id: tag.id, name: tag.name } },
          created_at:       t.created_at,
          updated_at:       t.updated_at
        }
      end

      private

      ConditionStruct = Struct.new(:field, :operator, :value)

      sig { params(conditions_data: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
      def condition_structs(conditions_data)
        conditions_data.map do |c|
          ConditionStruct.new(c[:field].to_s, c[:operator].to_s, c[:value].to_s)
        end
      end
    end
  end
end
