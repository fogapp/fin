# typed: strict

module Tax
  module Sections
    # Income facts for the year: interest/dividends from investment
    # transactions, realized gains from sales, equity compensation, plus
    # income adjustments. Wages remain an estimate off the profile.
    class Income < Base
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build
        dividends = @context.investment_transactions.dividends.sum(:income_usd).to_f.round(2)
        interest  = @context.investment_transactions.income
          .where.not(transaction_types: { category: InvestmentTransaction::DIVIDEND_CATEGORIES })
          .sum(:income_usd).to_f.round(2)

        {
          kind: "fact",
          wages: {
            kind:   "estimate",
            amount: @context.profile&.projected_wages.to_f,
            note:   "Projected wages from the tax profile — not paystub-derived"
          },
          interest:       interest,
          dividends:      dividends,
          realized_gains: realized_gains,
          equity_comp:    equity_comp,
          adjustments:    @context.adjustments_group(TaxAdjustment::Kind::Income)
        }
      end

      private

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def realized_gains
        sales = @context.investment_transactions.sales
        short = sales.sum(:gl_short_usd).to_f.round(2)
        long  = sales.sum(:gl_long_usd).to_f.round(2)

        rows = sales.where.not(security_id: nil)
                    .group(:security_id)
                    .pluck(:security_id,
                           Arel.sql("COALESCE(SUM(gl_short_usd), 0)"),
                           Arel.sql("COALESCE(SUM(gl_long_usd), 0)"))
        securities = Security.where(id: rows.map(&:first)).index_by(&:id)

        by_security = rows.map do |security_id, st, lt|
          security = securities[security_id]
          {
            security_id: security_id,
            label:       security && (security.ticker.presence || security.name.presence || security.cusip),
            short_term:  st.to_f.round(2),
            long_term:   lt.to_f.round(2),
            total:       (st.to_f + lt.to_f).round(2)
          }
        end
        by_security = by_security.reject { |r| r[:short_term].zero? && r[:long_term].zero? }
                                 .sort_by { |r| -r[:total].abs }
                                 .first(20)

        { short_term: short, long_term: long, total: (short + long).round(2), by_security: by_security }
      end

      # NSO exercises and RSU/RSA settlements produce ordinary income; ISO
      # exercises produce an AMT spread (NOT ordinary income). Events missing
      # a share price are listed but skipped from the totals, with a note.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def equity_comp
        events = EquityGrantEvent
          .where(household_id: @context.household.id, occurred_on: @context.range,
                 kind: EquityGrantEvent::ACQUIRING_KINDS)
          .includes(equity_grant: :equity_company)
          .order(:occurred_on, :created_at)

        ordinary   = 0.0
        amt_spread = 0.0
        skipped    = 0
        rows       = []

        events.each do |event|
          grant = event.equity_grant
          type  = grant.grant_type
          next unless (event.kind == EquityGrantEvent::Kind::Exercise && EquityGrant::OPTION_TYPES.include?(type)) ||
                      (event.kind == EquityGrantEvent::Kind::Settlement &&
                        [ EquityGrant::GrantType::Rsu, EquityGrant::GrantType::Rsa ].include?(type))

          row = {
            id:           event.id,
            kind:         event.kind,
            grant_type:   type,
            grant_label:  grant.label,
            company:      grant.equity_company&.name,
            occurred_on:  event.occurred_on,
            quantity:     event.quantity.to_f,
            share_price:  event.share_price&.to_f,
            strike_price: grant.strike_price&.to_f,
            ordinary_income: nil,
            amt_spread:      nil,
            # T.let so the shape admits the `true` assigned below for events with
            # no share price — a bare `false` literal types the key as FalseClass.
            skipped:         T.let(false, T::Boolean)
          }

          if event.share_price.nil?
            skipped += 1
            row[:skipped] = true
          else
            quantity = event.quantity.to_d
            price    = event.share_price.to_d
            spread   = [ price - grant.strike_price.to_d, BigDecimal("0") ].max

            if event.kind == EquityGrantEvent::Kind::Settlement
              amount = (price * quantity).to_f.round(2)
              ordinary += amount
              row[:ordinary_income] = amount
            elsif type == EquityGrant::GrantType::Nso
              amount = (spread * quantity).to_f.round(2)
              ordinary += amount
              row[:ordinary_income] = amount
            else # ISO exercise
              amount = (spread * quantity).to_f.round(2)
              amt_spread += amount
              row[:amt_spread] = amount
            end
          end

          rows << row
        end

        notes = []
        notes << "#{skipped} event(s) skipped from totals: no share price recorded" if skipped.positive?
        if iso_sales_in_year?
          notes << "ISO shares were sold this year — disqualifying-disposition detection is not modeled (v1), so some AMT spread may actually be ordinary income"
        end

        {
          ordinary_income: ordinary.round(2),
          iso_amt_spread:  amt_spread.round(2),
          events:          rows,
          notes:           notes
        }
      end

      sig { returns(T::Boolean) }
      def iso_sales_in_year?
        EquityGrantEvent
          .where(household_id: @context.household.id, kind: EquityGrantEvent::Kind::Sale, occurred_on: @context.range)
          .joins(:equity_grant)
          .where(equity_grants: { grant_type: EquityGrant::GrantType::Iso })
          .exists?
      end
    end
  end
end
