# typed: strict

module Tax
  # Household-wide wash-sale detection for one tax year — the check brokers
  # can't do, because they only see their own accounts. A finding is a loss
  # sale (negative gl_short + gl_long) with a purchase of the same security
  # in ANY of the household's accounts within ±30 days of the sale.
  # Repurchases inside retirement accounts are flagged `permanent` — the
  # disallowed loss is gone forever (Rev. Rul. 2008-5), not deferred into
  # basis.
  #
  # Warn-only by design: findings never adjust the realized-gains numbers.
  class WashSaleScanner
    extend T::Sig

    WINDOW_DAYS = 30

    sig { params(household: Household, year: Integer).void }
    def initialize(household:, year:)
      @household = household
      @year      = year
      @range     = T.let(Date.new(year, 1, 1)..Date.new(year, 12, 31), T::Range[Date])
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def findings
      loss_sales = InvestmentTransaction.sales
        .where(household_id: @household.id, trade_date: @range)
        .where.not(security_id: nil)
        .where("COALESCE(gl_short_usd, 0) + COALESCE(gl_long_usd, 0) < 0")
        .includes(:account, :security)
        .to_a
      return [] if loss_sales.empty?

      purchases = purchases_near(loss_sales)

      loss_sales.flat_map { |sale| findings_for(sale, purchases[sale.security_id] || []) }
                .sort_by { |f| [ f[:sale_date], f[:purchase_date] ] }
    end

    private

    sig { params(loss_sales: T::Array[InvestmentTransaction]).returns(T::Hash[T.untyped, T::Array[InvestmentTransaction]]) }
    def purchases_near(loss_sales)
      InvestmentTransaction.purchases
        .where(household_id: @household.id, security_id: loss_sales.map(&:security_id).uniq)
        .where(trade_date: (@range.first - WINDOW_DAYS)..(@range.last + WINDOW_DAYS))
        .includes(:account)
        .group_by(&:security_id)
    end

    sig { params(sale: InvestmentTransaction, candidates: T::Array[InvestmentTransaction]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def findings_for(sale, candidates)
      candidates
        .select { |p| p.id != sale.id && (p.trade_date - sale.trade_date).abs <= WINDOW_DAYS }
        .map do |purchase|
          purchase_account = T.must(purchase.account)
          {
            security_id:      sale.security_id,
            security_label:   security_label(sale.security),
            sale_date:        sale.trade_date,
            sale_account:     T.must(sale.account).name,
            loss:             (sale.gl_short_usd.to_f + sale.gl_long_usd.to_f).round(2),
            purchase_date:    purchase.trade_date,
            purchase_account: purchase_account.name,
            permanent:        Account::RETIREMENT_TREATMENTS.include?(purchase_account.tax_treatment)
          }
        end
    end

    sig { params(security: T.nilable(Security)).returns(T.nilable(String)) }
    def security_label(security)
      return nil if security.nil?

      security.ticker.presence || security.name.presence || security.cusip
    end
  end
end
