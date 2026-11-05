# typed: strict

module Office
  module Datasets
    # Cash transactions under the table's own filters. The column set
    # mirrors the browser CSV export (frontend/src/lib/csv.ts) so the two
    # downloads describe the same table, with ids added — a spreadsheet
    # someone pivots against wants a stable key per row.
    class Transactions
      extend T::Sig

      HEADER = T.let(
        [
          "Date", "Post date", "Description", "Merchant", "Category", "Parent category",
          "Account", "Amount", "Type", "Source", "Tags", "Memo", "Transaction ID"
        ].freeze,
        T::Array[String]
      )

      sig { params(params: T::Hash[Symbol, T.untyped]).void }
      def initialize(params)
        @params = T.let(params, T::Hash[Symbol, T.untyped])
      end

      sig { returns(Grid) }
      def grid
        scope = apply_transfer_visibility(apply_search(relation))
          .order(transaction_date: :desc, id: :desc)
          .includes(:merchant, { category: :parent }, :account, :tags)

        rows = [ HEADER ] + scope.map { |t| row(t) }
        Grid.new(title: title, rows: rows, filters: @params)
      end

      private

      # Two filter vocabularies reach this dataset. The transaction table
      # filters with rule conditions (field/operator/value), which only
      # Conditions::MatchQuery can evaluate; the account, category and
      # merchant pages scope by plain columns, which CashTransactions::Filter
      # handles. Whichever the caller sent is what the sheet reproduces.
      sig { returns(T.untyped) }
      def relation
        conditions = Array(@params[:conditions])
        return ::CashTransactions::Filter.new(@params).relation(::CashTransaction.all) if conditions.empty?

        ::Conditions::MatchQuery.new(
          resource_class: "CashTransaction",
          conditions:     conditions.map { |c| condition_struct(c) },
          match_all:      @params[:match_all] != false && @params[:match_all].to_s != "false",
          base_scope:     ::CashTransactions::Filter.new(@params).relation(::CashTransaction.all)
        ).relation
      end

      # The table's search box, server-side: every term must appear
      # somewhere in the description, merchant, category or amount, which is
      # what searchTransactions does in the browser. Without this the sheet
      # would quietly ignore a search the person could see narrowing the
      # table in front of them.
      sig { params(scope: T.untyped).returns(T.untyped) }
      def apply_search(scope)
        terms = @params[:search].to_s.split
        return scope if terms.empty?

        terms.reduce(scope.references(:merchant, :category).left_outer_joins(:merchant, :category)) do |acc, term|
          like = "%#{::ActiveRecord::Base.sanitize_sql_like(term)}%"
          acc.where(
            "cash_transactions.description ILIKE :q OR merchants.name ILIKE :q OR categories.name ILIKE :q " \
            "OR TO_CHAR(ABS(cash_transactions.amount), 'FM9999999990.00') LIKE :q",
            q: like
          )
        end
      end

      # The table's "show transfers" toggle: with it off, both legs of a
      # transfer are hidden except the outgoing leg of one that counts as
      # spending (a credit card payment, say).
      sig { params(scope: T.untyped).returns(T.untyped) }
      def apply_transfer_visibility(scope)
        return scope unless @params[:show_transfers].to_s == "false"

        scope.left_outer_joins(:transfer).where(
          "cash_transactions.transfer_id IS NULL OR (transfers.include_in_spend AND cash_transactions.amount < 0)"
        )
      end

      Condition = Struct.new(:field, :operator, :value)

      sig { params(raw: T.untyped).returns(T.untyped) }
      def condition_struct(raw)
        c = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
        c = c.symbolize_keys if c.respond_to?(:symbolize_keys)
        Condition.new(c[:field].to_s, c[:operator].to_s, c[:value].to_s)
      end

      sig { params(t: ::CashTransaction).returns(T::Array[T.untyped]) }
      def row(t)
        [
          t.transaction_date,
          t.post_date,
          t.description,
          t.merchant&.name,
          t.category&.name,
          t.category&.parent&.name,
          t.account&.name,
          t.amount.to_f,
          t.transaction_type,
          t.source,
          t.tags.map(&:name).join("; ").presence,
          t.memo,
          t.id
        ]
      end

      # Named for what it contains, since a household accumulates these:
      # "Transactions — Chase Checking, Jan 2026" beats three sheets all
      # called "Transactions".
      sig { returns(String) }
      def title
        parts = []
        account = ::Account.find_by(id: @params[:account_id])&.name if @params[:account_id].present?
        parts << account if account.present?
        parts << ::Category.find_by(id: @params[:category_id])&.name if @params[:category_id].present?
        parts << "“#{@params[:description]}”" if @params[:description].present?
        parts << window if window.present?
        count = Array(@params[:conditions]).size
        parts << (count == 1 ? "1 filter" : "#{count} filters") if count.positive?

        parts.compact_blank.any? ? "Transactions — #{parts.compact_blank.join(', ')}" : "Transactions"
      end

      sig { returns(T.nilable(String)) }
      def window
        from = @params[:start_date].presence || @params[:from].presence
        to   = @params[:end_date].presence || @params[:to].presence
        return nil if from.blank? && to.blank?

        [ from.presence || "start", to.presence || Date.current.to_s ].join(" to ")
      end
    end
  end
end
