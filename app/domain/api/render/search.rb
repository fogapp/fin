# typed: strict

module Api
  module Render
    # Sitewide Cmd+K search — one round trip returns a small ranked slice per
    # entity type, backed by the trgm GIN indexes from
    # 20260716000001_add_search_trgm_indexes.rb (ILIKE '%term%' can't use a
    # plain btree). Every model is household-scoped automatically via
    # HouseholdScoped's default_scope, except Security (a global catalog
    # table) — that one is scoped manually to what the household holds or
    # watches before any text match runs.
    class Search < Api::Render::Base
      extend T::Sig

      PER_GROUP_LIMIT = 5
      GROUPS = T.let(
        %i[merchants categories tags accounts transactions loans investment_transactions securities].freeze,
        T::Array[Symbol]
      )

      sig { returns(T::Hash[Symbol, T::Array[T::Hash[Symbol, T.untyped]]]) }
      def index
        q = params[:q].to_s.strip
        return GROUPS.index_with { [] } if q.blank?

        {
          merchants:               merchant_results(q),
          categories:              category_results(q),
          tags:                    tag_results(q),
          accounts:                account_results(q),
          transactions:            transaction_results(q),
          loans:                   loan_results(q),
          investment_transactions: investment_transaction_results(q),
          securities:              security_results(q)
        }
      end

      private

      sig { params(q: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def merchant_results(q)
        ranked(::Merchant.includes(:category), q, "merchants.name").map do |m|
          { id: m.id, name: m.name, category_name: m.category&.name }
        end
      end

      sig { params(q: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def category_results(q)
        ranked(::Category.includes(:parent), q, "categories.name").map do |c|
          { id: c.id, name: c.name, parent_name: c.parent&.name }
        end
      end

      sig { params(q: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def tag_results(q)
        ranked(::Tag, q, "tags.name").map { |t| { id: t.id, name: t.name } }
      end

      sig { params(q: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def account_results(q)
        ranked(::Account, q, "accounts.name").map do |a|
          { id: a.id, name: a.name, account_type: a.account_type, kind: a.kind }
        end
      end

      sig { params(q: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def transaction_results(q)
        ranked(
          ::CashTransaction.includes(:merchant, :category), q,
          "cash_transactions.description", "cash_transactions.memo",
          tiebreak: "cash_transactions.transaction_date DESC"
        ).map do |t|
          {
            id: t.id, description: t.description, amount: t.amount&.to_f,
            transaction_date: t.transaction_date,
            merchant_name: t.merchant&.name, category_name: t.category&.name
          }
        end
      end

      sig { params(q: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def loan_results(q)
        ranked(::Loan, q, "loans.name", "loans.lender").map do |l|
          { id: l.id, name: l.name, lender: l.lender }
        end
      end

      sig { params(q: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def investment_transaction_results(q)
        ranked(
          ::InvestmentTransaction.includes(:security), q, "investment_transactions.description"
        ).map do |it|
          {
            id: it.id, description: it.description, amount: it.amount_usd&.to_f,
            trade_date: it.trade_date, security_id: it.security_id,
            security_ticker: it.security&.ticker, security_name: it.security&.name
          }
        end
      end

      # Securities carry no household_id — collect the ids this household
      # actually holds (investment_transactions) or watches (security_watches)
      # first, both of which *are* household-scoped, then match text only
      # within that set. Skipping this would leak every household's holdings
      # to every other household on a matching query.
      sig { params(q: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def security_results(q)
        # EXISTS instead of plucking every held/watched id per keystroke —
        # the old form scanned the whole (household-scoped) investment
        # ledger before the text match even ran. Building the subqueries as
        # relations keeps HouseholdScoped's default_scope on both.
        held    = ::InvestmentTransaction.where("investment_transactions.security_id = securities.id")
        watched = ::SecurityWatch.where("security_watches.security_id = securities.id")
        scope   = ::Security.where(held.arel.exists).or(::Security.where(watched.arel.exists))

        ranked(scope, q, "securities.name", "securities.ticker").map do |s|
          { id: s.id, name: s.name, ticker: s.ticker, security_type: s.security_type }
        end
      end

      # Prefix-match-first ILIKE search across one or more columns. `columns`
      # (and `tiebreak`) are always hardcoded at the call site, never user
      # input — only `q` needs sanitizing.
      sig { params(relation: T.untyped, q: String, columns: String, tiebreak: T.nilable(String)).returns(T.untyped) }
      def ranked(relation, q, *columns, tiebreak: nil)
        like   = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
        prefix = "#{ActiveRecord::Base.sanitize_sql_like(q)}%"

        where_sql = columns.map { |c| "#{c} ILIKE :like" }.join(" OR ")
        rank_sql  = columns.map { |c| "(CASE WHEN #{c} ILIKE ? THEN 0 ELSE 1 END)" }.join(" + ")
        rank_expr = ActiveRecord::Base.sanitize_sql_array([ rank_sql, *Array.new(columns.size, prefix) ])

        order_clauses = [ Arel.sql(rank_expr) ]
        order_clauses << Arel.sql(tiebreak) if tiebreak
        order_clauses << Arel.sql(T.must(columns.first))

        relation
          .where(where_sql, like: like)
          .order(*order_clauses)
          .limit(PER_GROUP_LIMIT)
      end
    end
  end
end
