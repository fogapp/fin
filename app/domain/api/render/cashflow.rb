# typed: strict

module Api
  module Render
    # Response assembly for the cashflow endpoints. The analytics live in
    # ::Cashflow::{Outliers, SankeyGraph, Breakdown}; this class owns param
    # handling, scoping, and payload shape.
    class Cashflow < Api::Render::Base
      extend T::Sig

      include Concerns::WindowAggregates

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def index
        today         = Date.current
        ytd_from      = today.beginning_of_year
        range_from    = date_param(:from) || ytd_from
        this_mo_start = today.beginning_of_month
        last_mo_start = (today - 1.month).beginning_of_month
        last_mo_end   = this_mo_start - 1.day

        income_scope = income_like_scoped
        spend_scope  = spend_like_scoped

        monthly_income = monthly_series(income_scope, window_from, to: window_to, round: 2)
        monthly_spend  = monthly_series(spend_scope, window_from, to: window_to, negate: true, round: 2)

        windows = [ ytd_from.., this_mo_start.., last_mo_start..last_mo_end ]
        ytd_income, mtd_income, lmo_income = window_aggregates(income_scope, windows).map { |v| v.to_f.round(2) }
        ytd_spend,  mtd_spend,  lmo_spend  = window_aggregates(spend_scope, windows).map { |v| (-v.to_f).round(2) }

        savings_rate_ytd = ytd_income > 0 ? (((ytd_income - ytd_spend) / ytd_income) * 100).round(1) : nil

        # Outlier detection needs to cover every window this action reports
        # on (the chart's window, YTD, and last-month, which can spill into
        # the prior year in January) — not just window_from..window_to —
        # otherwise mtd/lmo/ytd "common" totals below would silently miss
        # outliers outside whatever the timeframe selector happens to cover.
        # Computed once and reused for the Outliers panel, the chart's
        # monthly "common" series, and every "common" total below, instead
        # of re-scanning transactions per window.
        flagged_from = [ window_from, ytd_from, last_mo_start ].min
        flagged_to   = [ window_to, today ].max
        flagged      = outliers.flagged(flagged_from..flagged_to)
        excluded_ids = flagged.map { |row| row[:transaction_id] }

        mtd_spend_common = (mtd_spend - ::Cashflow::Outliers.sum_in(flagged, this_mo_start..)).round(2)
        lmo_spend_common = (lmo_spend - ::Cashflow::Outliers.sum_in(flagged, last_mo_start..last_mo_end)).round(2)
        ytd_spend_common = (ytd_spend - ::Cashflow::Outliers.sum_in(flagged, ytd_from..)).round(2)

        # Drill-downs must use the same spend_like definition as the summary
        # totals above — they used to hardcode "credit-card Sales only",
        # which silently excluded bank-sourced debits (e.g. wires, checks)
        # from every category/merchant breakdown while still counting them
        # in ytd_spend/mtd_spend, making the totals not add up to the parts.
        months = month_count(range_from, window_to)

        category_scope = category_spend_scope(range_from..window_to)
        top_categories        = ::Cashflow::Breakdown.ranked(category_scope, id_expr: category_id_expr, name_expr: category_name_expr, months: months)
        top_categories_common = ::Cashflow::Breakdown.ranked(category_scope.where.not(id: excluded_ids), id_expr: category_id_expr, name_expr: category_name_expr, months: months)

        merchant_scope = merchant_spend_scope(range_from..window_to)
        top_merchants        = ::Cashflow::Breakdown.ranked(merchant_scope, id_expr: "merchants.id", name_expr: "merchants.name", months: months)
        top_merchants_common = ::Cashflow::Breakdown.ranked(merchant_scope.where.not(id: excluded_ids), id_expr: "merchants.id", name_expr: "merchants.name", months: months)

        top_income_sources = income_scope
          .joins("LEFT JOIN merchants ON merchants.id = cash_transactions.merchant_id")
          .where(transaction_date: range_from..window_to)
          .group("COALESCE(merchants.name, cash_transactions.description)")
          .sum(:amount)
          .transform_values { |v| v.to_f.round(2) }
          .sort_by { |_, v| -v }
          .first(8)
          .to_h

        {
          summary: {
            mtd_income:        mtd_income,
            mtd_spend:         mtd_spend,
            mtd_spend_common:  mtd_spend_common,
            mtd_net:           (mtd_income - mtd_spend).round(2),
            lmo_income:        lmo_income,
            lmo_spend:         lmo_spend,
            lmo_spend_common:  lmo_spend_common,
            ytd_income:        ytd_income,
            ytd_spend:         ytd_spend,
            ytd_spend_common:  ytd_spend_common,
            ytd_net:           (ytd_income - ytd_spend).round(2),
            savings_rate_ytd:  savings_rate_ytd
          },
          # Audit row: money moved to cards, excluded from the totals above —
          # visible so exclusions stay explainable ("exclude but don't hide").
          card_payments: {
            mtd: card_payments_total(this_mo_start..today),
            lmo: card_payments_total(last_mo_start..last_mo_end),
            # Card spend over the same trailing window, for the "am I paying
            # off what I swipe?" comparison.
            card_spend_90d: (-spend_like_scoped.source_credit_card
                               .where(transaction_date: (today - 90)..today)
                               .sum(:amount).to_f).round(2),
            paid_90d: card_payments_total((today - 90)..today)
          },
          # Data-quality chip: unlinked payment-shaped debits still counted
          # in spending, awaiting review or a late counterpart.
          payment_suspects: apply_scope(::CashTransaction.payment_suspects)
                              .where(transaction_date: range_from..window_to)
                              .count,
          monthly_income:         monthly_income,
          monthly_spend:          monthly_spend,
          monthly_spend_common:   ::Cashflow::Outliers.monthly_common(flagged, monthly_spend),
          top_categories:         top_categories,
          top_categories_common:  top_categories_common,
          top_merchants:          top_merchants,
          top_merchants_common:   top_merchants_common,
          top_income_sources:     top_income_sources,
          outliers:               ::Cashflow::Outliers.top(flagged, range_from..window_to)
        }
      end

      # What the spend side of the sankey fans out into. "category_group"
      # rolls subcategories up into their parent; "merchant" ignores
      # categorization entirely.
      class SankeyDimension < T::Enum
        extend T::Sig

        include ApplicationEnum

        enums do
          Category = new("category")
          CategoryGroup = new("category_group")
          Merchant = new("merchant")
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def sankey
        from = date_param(:from) || 5.months.ago.to_date.beginning_of_month
        to   = date_param(:to) || Date.current
        # Validated against SankeyDimension by the controller before we run.
        dimension = params[:dimension].presence || "category"

        income_scope = income_like_scoped.where(transaction_date: from..to)
        spend_scope  = spend_like_scoped.where(transaction_date: from..to)

        # Both the as-it-happened graph and the outlier-excluded ("common")
        # variant ship in one response so the section's Common toggle stays
        # instant — the variants share the fence computation, which is the
        # expensive part. The flagged ids ride along so the node drill-down's
        # transaction list can drop exactly the rows the common graph did.
        flagged      = outliers.flagged(from..to)
        excluded_ids = flagged.map { |row| row[:transaction_id] }

        common = ::Cashflow::SankeyGraph
          .call(income_scope: income_scope, spend_scope: spend_scope.where.not(id: excluded_ids), dimension: dimension)
          .merge(outlier_transaction_ids: excluded_ids)

        {
          from: from.to_s, to: to.to_s,
          **::Cashflow::SankeyGraph.call(income_scope: income_scope, spend_scope: spend_scope, dimension: dimension),
          common: common
        }
      end

      # Per-month spend split by category / merchant, for the Spending chart's
      # stacked and share-of-total modes. Deliberately NOT part of #index: only
      # those modes need it, while #index's payload is also what the dashboard
      # widgets and the MCP tool fetch, and this would roughly triple it.
      #
      # Both the total and the outlier-excluded ("common") variant ship in one
      # response so the page's Common/Outlier toggle stays instant — the
      # variants share the fence computation, which is the expensive part.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def spend_breakdown
        window = window_from..window_to

        monthly_total = monthly_series(spend_like_scoped, window_from, to: window_to, negate: true, round: 2)

        flagged              = outliers.flagged(window)
        excluded_ids         = flagged.map { |row| row[:transaction_id] }
        monthly_total_common = ::Cashflow::Outliers.monthly_common(flagged, monthly_total)

        category_scope = category_spend_scope(window)
        merchant_scope = merchant_spend_scope(window)

        {
          from: window_from.to_s,
          to:   window_to.to_s,
          # The Total line's series ride along (they're already computed as the
          # stacks' reconciliation totals), so a page without its own cashflow
          # payload — a category or tag detail — can power the whole spend
          # chart from this one endpoint.
          monthly_spend:        monthly_total,
          monthly_spend_common: monthly_total_common,
          category: ::Cashflow::Breakdown.monthly(
            category_scope, id_expr: category_id_expr, name_expr: category_name_expr, monthly_total: monthly_total
          ),
          category_common: ::Cashflow::Breakdown.monthly(
            category_scope.where.not(id: excluded_ids),
            id_expr: category_id_expr, name_expr: category_name_expr, monthly_total: monthly_total_common
          ),
          merchant: ::Cashflow::Breakdown.monthly(
            merchant_scope, id_expr: "merchants.id", name_expr: "merchants.name", monthly_total: monthly_total
          ),
          merchant_common: ::Cashflow::Breakdown.monthly(
            merchant_scope.where.not(id: excluded_ids),
            id_expr: "merchants.id", name_expr: "merchants.name", monthly_total: monthly_total_common
          )
        }
      end

      private

      # Fences honor the same account/tag/category scoping as every other
      # number here — a fence sized on the whole household would flag rows a
      # single-account view can't explain.
      sig { returns(::Cashflow::Outliers) }
      def outliers
        @outliers ||= T.let(::Cashflow::Outliers.new(spend_scope: spend_like_scoped), T.nilable(::Cashflow::Outliers))
      end

      # Optional account/tag/category scoping, honored by every number this
      # renderer produces (summaries, drill-downs, the sankey, and the outlier
      # fences). card_payments stays unscoped: it's a transfer-pair audit row,
      # and a payment's two legs live in different accounts by definition.
      sig { params(scope: T.untyped).returns(T.untyped) }
      def apply_scope(scope)
        # Only the scoping subset: cashflow's date windows are computed
        # per-metric (YTD, MTD, chart window), never as a blanket row filter.
        filter.relation(scope, only: ::CashTransactions::Filter::SCOPE_KEYS)
      end

      # Memoized so category_id's rollup lookup runs once per request, not
      # once per scoped metric.
      sig { returns(::CashTransactions::Filter) }
      def filter
        @filter ||= T.let(::CashTransactions::Filter.new(params), T.nilable(::CashTransactions::Filter))
      end

      sig { returns(T.untyped) }
      def income_like_scoped
        apply_scope(::CashTransaction.income_like)
      end

      sig { returns(T.untyped) }
      def spend_like_scoped
        apply_scope(::CashTransaction.spend_like)
      end

      # The chart window, shared by #index and #spend_breakdown so the stacked
      # modes span exactly the months the Total line does.
      sig { returns(Date) }
      def window_from
        @window_from ||= T.let(
          date_param(:from) || (::CashTransaction.minimum(:transaction_date) || 1.year.ago.to_date).beginning_of_month,
          T.nilable(Date)
        )
      end

      sig { returns(Date) }
      def window_to
        @window_to ||= T.let(date_param(:to) || Date.current, T.nilable(Date))
      end

      # Categorized spend. Inner join: uncategorized rows are invisible to the
      # ranked panels, and fall into the stacked charts' "other" remainder.
      # The parent join feeds the category_*_expr rollup.
      sig { params(range: T::Range[Date]).returns(T.untyped) }
      def category_spend_scope(range)
        spend_like_scoped
          .joins(:category)
          .joins("LEFT JOIN categories parent_categories ON parent_categories.id = categories.parent_id")
          .where(transaction_date: range)
      end

      # What a "category" row is. Household-wide, subcategories roll up into
      # their parent — otherwise Home › Mortgage ranks beside Dining Out as
      # if they were peers. Scoped to one category (its detail page), the
      # split is by subcategory instead: rolled up, that page would only
      # ever show a single band.
      sig { returns(T::Boolean) }
      def roll_up_subcategories?
        params[:category_id].blank?
      end

      sig { returns(String) }
      def category_id_expr
        roll_up_subcategories? ? "COALESCE(parent_categories.id, categories.id)" : "categories.id"
      end

      sig { returns(String) }
      def category_name_expr
        roll_up_subcategories? ? "COALESCE(parent_categories.name, categories.name)" : "categories.name"
      end

      # Merchant-attributed spend, same story for rows with no merchant.
      sig { params(range: T::Range[Date]).returns(T.untyped) }
      def merchant_spend_scope(range)
        spend_like_scoped
          .joins("LEFT JOIN merchants ON merchants.id = cash_transactions.merchant_id")
          .where(transaction_date: range)
          .where("merchants.id IS NOT NULL")
      end

      # Confirmed card-payment volume in the window. Summed per transfer (a
      # pair has two legs — summing legs would double-count) and a transfer is
      # in-window when either leg's date is.
      sig { params(range: T::Range[Date]).returns(Float) }
      def card_payments_total(range)
        ids = ::Transfer.confirmed.where(kind: ::Transfer::Kind::CreditCardPayment)
          .joins("JOIN cash_transactions legs ON legs.transfer_id = transfers.id")
          .where(legs: { transaction_date: range })
          .distinct
          .select("transfers.id")
        ::Transfer.where(id: ids).sum(:amount).to_f.round(2).to_f
      end

      # negate (not abs) for spend series: spend is stored negative, and a
      # net-credit month should stay negative instead of flipping sign.
      sig { params(scope: T.untyped, from: T.untyped, to: T.untyped, negate: T::Boolean, round: T.untyped).returns(T.untyped) }
      def monthly_series(scope, from, to: Date.current, negate: false, round: nil)
        scope
          .where(transaction_date: from..to)
          .group_by_period(:month, :transaction_date)
          .sum(:amount)
          .transform_keys(&:to_s)
          .transform_values do |v|
            result = negate ? -v.to_f : v.to_f
            round ? result.round(round) : result
          end
      end

      # Inclusive month count spanning `from..to` (Jan..Mar = 3), floored at
      # 1 so a same-month window never divides avg_monthly by zero.
      sig { params(from: Date, to: Date).returns(Integer) }
      def month_count(from, to)
        [ (to.year - from.year) * 12 + (to.month - from.month) + 1, 1 ].max
      end
    end
  end
end
