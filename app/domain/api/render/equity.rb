# typed: strict

module Api
  module Render
    # Serializes the /api/v1/equity surface: one rich summary payload
    # (companies → fmv history + grants → tranches/events + totals) and the
    # per-record shapes the mutation endpoints return. Numbers are floats.
    class Equity < Api::Render::Base
      extend T::Sig

      UPCOMING_HORIZON_DAYS = 365

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def summary
        companies = ::EquityCompany
          .includes(:security, :fmv_entries, grants: :events)
          .order(:name)
          .to_a

        {
          companies: companies.map { |c| company(c) },
          totals:    totals(companies)
        }
      end

      sig { params(company: ::EquityCompany).returns(T::Hash[Symbol, T.untyped]) }
      def company(company)
        price  = share_price(company)
        latest = company.latest_fmv

        {
          id:             company.id,
          name:           company.name,
          public_company: company.public_company?,
          security_id:    company.security_id,
          ticker:         company.security&.ticker,
          c_corp:         company.c_corp?,
          qsbs_candidate: company.qsbs_candidate?,
          preferred_price: company.preferred_price&.to_f,
          notes:          company.notes,
          share_price:    price&.to_f,
          latest_fmv:     latest && {
            price_per_share: latest.price_per_share.to_f,
            effective_date:  latest.effective_date,
            source:          latest.source,
            stale:           latest.stale?
          },
          fmv_entries:    company.fmv_entries.sort_by(&:effective_date).reverse.map { |e| fmv_entry(e) },
          grants:         company.grants.sort_by { |g| [ g.grant_date, g.created_at ] }.map { |g| grant(g, price: price) }
        }
      end

      sig { params(entry: ::EquityFmvEntry).returns(T::Hash[Symbol, T.untyped]) }
      def fmv_entry(entry)
        {
          id:              entry.id,
          price_per_share: entry.price_per_share.to_f,
          effective_date:  entry.effective_date,
          source:          entry.source
        }
      end

      sig { params(grant: ::EquityGrant, price: T.nilable(BigDecimal)).returns(T::Hash[Symbol, T.untyped]) }
      def grant(grant, price: nil)
        price ||= share_price(T.must(grant.equity_company))
        calculator = calculator_for(grant)
        tranches   = calculator.tranches
        vested     = calculator.vested_quantity
        unvested   = calculator.unvested_quantity
        next_vest  = calculator.next_vest

        {
          id:                        grant.id,
          label:                     grant.label,
          grant_type:                grant.grant_type,
          grant_date:                grant.grant_date,
          vesting_commencement_date: grant.vesting_commencement_date,
          quantity:                  grant.quantity.to_f,
          strike_price:              grant.strike_price&.to_f,
          early_exercisable:         grant.early_exercisable?,
          double_trigger:            grant.double_trigger?,
          expiration_date:           grant.expiration_date,
          pte_window_days:           grant.pte_window_days,
          vesting_interval:          grant.vesting_interval,
          vesting_occurrences:       grant.vesting_occurrences,
          cliff_installments:        grant.cliff_installments,
          custom_tranches:           grant.custom_tranches,
          notes:                     grant.notes,
          vested_quantity:           vested.to_f,
          unvested_quantity:         unvested.to_f,
          exercised_quantity:        grant.exercised_quantity.to_f,
          settled_quantity:          grant.settled_quantity.to_f,
          sold_quantity:             grant.sold_quantity.to_f,
          vested_value:              ::Equity::Valuation.grant_value(grant, vested, price)&.to_f,
          unvested_value:            ::Equity::Valuation.grant_value(grant, unvested, price)&.to_f,
          next_vest:                 next_vest && { date: next_vest[:date], quantity: next_vest[:quantity].to_f },
          tranches:                  tranches.map { |t|
            { date: t[:date], quantity: t[:quantity].to_f, vested: t[:date] <= Date.current }
          },
          events:                    grant.events.sort_by { |e| [ e.occurred_on, e.created_at ] }.reverse.map { |e| event(e) }
        }
      end

      sig { params(event: ::EquityGrantEvent).returns(T::Hash[Symbol, T.untyped]) }
      def event(event)
        {
          id:                event.id,
          kind:              event.kind,
          occurred_on:       event.occurred_on,
          quantity:          event.quantity.to_f,
          share_price:       event.share_price&.to_f,
          method:            event[:method],
          buyer_type:        event.buyer_type,
          election_83b:      event.election_83b?,
          election_83b_date: event.election_83b_date,
          shares_withheld:   event.shares_withheld&.to_f,
          notes:             event.notes
        }
      end

      private

      # summary serializes each company and grant, then walks them all again
      # for totals: price lookups (a quote or FMV read) and vesting schedules
      # are computed once per record per render.
      sig { params(company: ::EquityCompany).returns(T.nilable(BigDecimal)) }
      def share_price(company)
        @share_prices ||= T.let({}, T.nilable(T::Hash[String, T.nilable(BigDecimal)]))
        return @share_prices[company.id] if @share_prices.key?(company.id)

        @share_prices[company.id] = ::Equity::Valuation.current_share_price(company)
      end

      sig { params(grant: ::EquityGrant).returns(::Equity::VestingCalculator) }
      def calculator_for(grant)
        @calculators ||= T.let({}, T.nilable(T::Hash[String, ::Equity::VestingCalculator]))
        @calculators[grant.id] ||= grant.calculator
      end

      sig { params(companies: T::Array[::EquityCompany]).returns(T::Hash[Symbol, T.untyped]) }
      def totals(companies)
        vested_value   = BigDecimal("0")
        unvested_value = BigDecimal("0")
        upcoming       = []
        today          = Date.current
        horizon        = today + UPCOMING_HORIZON_DAYS

        companies.each do |company|
          price = share_price(company)
          company.grants.each do |grant|
            calculator = calculator_for(grant)
            vested_value   += ::Equity::Valuation.grant_value(grant, calculator.vested_quantity, price) || 0
            unvested_value += ::Equity::Valuation.grant_value(grant, calculator.unvested_quantity, price) || 0

            calculator.tranches.each do |tranche|
              next unless tranche[:date] > today && tranche[:date] <= horizon

              upcoming << {
                date:         tranche[:date],
                quantity:     tranche[:quantity].to_f,
                value:        ::Equity::Valuation.grant_value(grant, tranche[:quantity], price)&.to_f,
                grant_id:     grant.id,
                grant_label:  grant.label,
                grant_type:   grant.grant_type,
                company_id:   company.id,
                company_name: company.name
              }
            end
          end
        end

        {
          vested_value:   vested_value.to_f,
          unvested_value: unvested_value.to_f,
          upcoming_vests: upcoming.sort_by { |v| v[:date] }
        }
      end
    end
  end
end
