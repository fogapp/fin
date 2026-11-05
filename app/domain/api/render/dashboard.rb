# typed: strict

module Api
  module Render
    class Dashboard < Api::Render::Base
      extend T::Sig

      include Concerns::WindowAggregates

      ACTIVITY_BUCKETS = T.let({
        ::TransactionType::Category::DIVIDEND                  => "Dividends",
        ::TransactionType::Category::FOREIGN_DIVIDEND          => "Dividends",
        ::TransactionType::Category::PURCHASE                  => "Buys",
        ::TransactionType::Category::SALE                      => "Sells",
        ::TransactionType::Category::INTEREST                  => "Interest",
        ::TransactionType::Category::MUNICIPAL_INTEREST        => "Interest",
        ::TransactionType::Category::ACCRUED_INTEREST_PAID     => "Interest",
        ::TransactionType::Category::ACCRUED_INTEREST_RECEIVED => "Interest",
        ::TransactionType::Category::FEES                      => "Fees",
        ::TransactionType::Category::COMMISSIONS               => "Fees",
        ::TransactionType::Category::TRANSFER_IN               => "Transfers",
        ::TransactionType::Category::TRANSFER_OUT              => "Transfers"
      }.freeze, T::Hash[String, String])

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def index
        account_ids    = resolve_account_ids
        inv            = scoped_inv(account_ids)
        snap           = scoped_snap(account_ids)
        window_from    = date_param(:from) || 11.months.ago.beginning_of_month.to_date
        ytd_from       = Date.current.beginning_of_year
        portfolio_date = snap.maximum(:as_of_date)
        # The same resolution the Investments page uses (per-account species
        # precedence and staleness), not "every snapshot on the latest date",
        # which drops any account whose last snapshot is older.
        current         = ::Positions::CurrentPositions.new.relation
        portfolio_scope = account_ids ? current.where(account_id: account_ids) : current

        {
          stats:               stats(inv, portfolio_scope, ytd_from, account_ids),
          portfolio_chart:     portfolio_chart(inv, snap, portfolio_date, account_ids),
          allocation:          allocation(portfolio_scope),
          income_series:       income_series(inv, window_from),
          activity_chart:      activity_chart(inv, window_from),
          monthly_spend:       monthly_spend(window_from, account_ids),
          compact_stats:       compact_stats(account_ids),
          recent_transactions: recent_transactions(inv, account_ids)
        }
      end

      private

      sig { returns(T.untyped) }
      def resolve_account_ids
        return nil if params[:broker_id].blank?
        broker = ::Broker.find(params[:broker_id])
        broker.accounts.pluck(:id)
      end

      sig { params(account_ids: T.untyped).returns(T.untyped) }
      def scoped_inv(account_ids)
        account_ids ? InvestmentTransaction.where(account_id: account_ids) : InvestmentTransaction.all
      end

      sig { params(account_ids: T.untyped).returns(T.untyped) }
      def scoped_snap(account_ids)
        account_ids ? PositionSnapshot.where(account_id: account_ids) : PositionSnapshot.all
      end

      # Every block below must respect the optional broker filter
      # (account_ids) — a filtered dashboard used to silently mix global and
      # broker-scoped numbers.
      sig { params(inv: T.untyped, portfolio_scope: T.untyped, ytd_from: T.untyped, account_ids: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def stats(inv, portfolio_scope, ytd_from, account_ids)
        ytd_income = inv.income.where(trade_date: ytd_from..)
        {
          portfolio_value: portfolio_scope.sum(:market_value).to_f,
          unrealized:      portfolio_scope.sum(:unrealized_gain_loss).to_f,
          cost_basis:      portfolio_scope.sum(:cost_basis).to_f,
          transactions:    inv.count + scoped_cash(account_ids).count,
          income_ytd:      ytd_income.sum(:income_usd).to_f
        }
      end

      sig { params(account_ids: T.untyped).returns(T.untyped) }
      def scoped_cash(account_ids)
        account_ids ? ::CashTransaction.where(account_id: account_ids) : ::CashTransaction.all
      end

      sig { params(inv: T.untyped, snap: T.untyped, portfolio_date: T.untyped, account_ids: T.untyped).returns(T::Hash[String, Float]) }
      def portfolio_chart(inv, snap, portfolio_date, account_ids)
        return {} unless portfolio_date

        earliest   = inv.minimum(:trade_date) || portfolio_date
        window_from = [ portfolio_date - 1.year, earliest ].max

        # Same engine as the Portfolio page and net worth, so none of them
        # can disagree.
        ::Valuation::PortfolioSeries.call(from: window_from, to: portfolio_date, account_ids: account_ids)
      end

      sig { params(portfolio_scope: T.untyped).returns(T.untyped) }
      def allocation(portfolio_scope)
        portfolio_scope
          .group(Arel.sql("COALESCE(NULLIF(asset_class, ''), 'Other')"))
          .sum(:market_value)
          .transform_values { |v| v.to_f.round(2) }
          .sort_by { |_, v| -v }
          .to_h
      end

      # Same definition as cashflow's monthly_spend (spend_like, negated not
      # abs'd), so this widget agrees with the "This Month" widget beside it.
      # `.sales` used to count transfer-linked bank debits and skip returns.
      sig { params(window_from: T.untyped, account_ids: T.untyped).returns(T.untyped) }
      def monthly_spend(window_from, account_ids)
        scoped_cash(account_ids).spend_like
                         .where(transaction_date: window_from..)
                         .group_by_period(:month, :transaction_date)
                         .sum(:amount)
                         .transform_keys(&:to_s)
                         .transform_values { |v| (-v.to_f).round(2) }
      end

      sig { params(inv: T.untyped, window_from: T.untyped).returns(T.untyped) }
      def income_series(inv, window_from)
        inv.income
           .where(trade_date: window_from..)
           .group_by_period(:month, :trade_date)
           .sum(:income_usd)
           .transform_keys(&:to_s)
           .transform_values { |v| v.to_f.round(2) }
      end

      sig { params(inv: T.untyped, window_from: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def activity_chart(inv, window_from)
        raw = inv
          .joins(:transaction_type)
          .where(trade_date: window_from..)
          .group_by_period(:month, :trade_date)
          .group("transaction_types.category")
          .count

        months  = raw.keys.map(&:first).uniq.sort.map(&:to_s)
        buckets = Hash.new { |h, k| h[k] = Hash.new(0) }

        raw.each do |(month, category), count|
          buckets[ACTIVITY_BUCKETS[category] || "Other"][month.to_s] += count
        end

        # Colors are a presentation concern — the chart theme assigns series
        # slots client-side by this fixed bucket order.
        buckets.map do |bucket, data|
          {
            name: bucket,
            data: months.map { |m| [ m, data[m].to_i ] }
          }
        end
      end

      sig { params(account_ids: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def compact_stats(account_ids)
        today         = Date.current
        this_mo_start = today.beginning_of_month
        last_mo_start = (today - 1.month).beginning_of_month
        this_mo       = this_mo_start..today
        last_mo       = last_mo_start..(last_mo_start + (today.day - 1))

        # Each figure uses the same definition as the stat page its ribbon
        # item links to (Metrics::Definitions::MonthlySpend, MonthlyIncome,
        # CcTransactionCount, CcAvgTransaction). `.sales` used to count
        # transfer-linked bank debits as spend, the card scope counted
        # autopayments (imported as Returns), and income summed investment
        # income while linking to bank deposits.
        all_spend = scoped_cash(account_ids).spend_like
        cc_spend  = all_spend.source_credit_card
        income    = scoped_cash(account_ids).income_like

        windows = [ this_mo, last_mo ]
        this_spend, last_spend   = window_aggregates(all_spend, windows).map { |v| -v.to_f }
        this_count, last_count   = window_aggregates(cc_spend, windows, count: true).map(&:to_i)
        this_cc_sum, last_cc_sum = window_aggregates(cc_spend, windows).map { |v| -v.to_f }
        this_avg   = this_count > 0 ? (this_cc_sum / this_count).round(2) : nil
        last_avg   = last_count > 0 ? (last_cc_sum / last_count).round(2) : nil

        this_income, last_income = window_aggregates(income, windows).map(&:to_f)

        {
          spend:           this_spend,
          spend_change:    pct_change(this_spend, last_spend),
          income:          this_income,
          income_change:   pct_change(this_income, last_income),
          cc_count:        this_count,
          cc_count_change: pct_change(this_count, last_count),
          cc_avg:          this_avg,
          cc_avg_change:   pct_change(this_avg, last_avg)
        }
      end

      sig { params(inv: T.untyped, account_ids: T.untyped).returns(T.untyped) }
      def recent_transactions(inv, account_ids)
        inv_rows = inv.includes(:account, :security, :transaction_type)
                      .recent
                      .limit(20)
                      .map do |t|
          {
            kind:             "investment",
            date:             t.trade_date,
            description:      t.description,
            amount:           t.amount_usd.to_f,
            account_name:     t.account.name,
            secondary:        t.security&.ticker,
            transaction_type: t.transaction_type.code_description
          }
        end

        cash_rows = scoped_cash(account_ids).includes(:merchant, :account)
                                     .where.not(transaction_type: ::CashTransaction::TransactionType::Payment.serialize)
                                     .order(transaction_date: :desc)
                                     .limit(20)
                                     .map do |t|
          {
            kind:             "cash",
            date:             t.transaction_date,
            description:      t.description,
            amount:           t.amount.to_f,
            account_name:     t.account&.name,
            secondary:        t.merchant&.name,
            transaction_type: t.transaction_type
          }
        end

        (inv_rows + cash_rows)
          .sort_by { |r| r[:date] }
          .reverse
          .first(20)
      end
    end
  end
end
