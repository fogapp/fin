# typed: strict

module MarketData
  # Second-source price verification: for every candle link whose instrument
  # is also covered by another configured provider, fetch the recent window
  # from that secondary source and compare raw closes date-by-date against
  # the stored series. Disagreement beyond tolerance raises a per-security
  # Issue for the households holding or watching it (auto-resolving once the
  # sources agree again), so silent bad prices turn into an inbox item.
  #
  # Raw close — not adjusted_close — is compared: providers share the
  # official close but differ in adjustment methodology over long histories.
  module CrossCheck
    extend T::Sig

    WINDOW_DAYS = 30
    # Equities share an official exchange close; crypto "closes" come from
    # different exchange baskets and day-boundary conventions, so the band
    # is wider.
    EQUITY_TOLERANCE = T.let(BigDecimal("0.005"), BigDecimal)
    CRYPTO_TOLERANCE = T.let(BigDecimal("0.02"), BigDecimal)

    ISSUE_SOURCE = "market_data.cross_check"

    Result = Struct.new(:checked, :clean, :mismatched, :skipped, keyword_init: true)

    Mismatch = Struct.new(:date, :stored, :observed, keyword_init: true)

    sig { params(pace: T::Boolean).returns(Result) }
    def self.run(pace: true)
      # Cross-checking is global shared-market-data work: neutralize any
      # ambient household so household-scoped reads/resolves (Issue) see
      # every household, and report! opts back in per audience household.
      Current.set(household: nil) { run_all(pace: pace) }
    end

    sig { params(pace: T::Boolean).returns(Result) }
    def self.run_all(pace:)
      result = Result.new(checked: 0, clean: 0, mismatched: 0, skipped: 0)

      InstrumentDataLink.enabled.where(capability: Capability::Candles.serialize).find_each do |link|
        security = Security.unscoped.find_by(id: link.security_id)
        next if security.nil? || security.ticker.blank?

        secondary = Router.secondary_provider(security, Capability::Candles, T.unsafe(link).provider)
        if secondary.nil?
          result.skipped += 1
          next
        end

        check_one(security, secondary, result)
        sleep(pace_for(secondary)) if pace
      rescue => e
        # A cross-check failure is not a data problem — log and move on so
        # one bad ticker doesn't stall verification of the rest.
        result.skipped += 1
        Rails.logger.warn("[MarketData::CrossCheck] #{security&.ticker} via #{secondary&.serialize} failed: #{e.class}: #{e.message}")
      end

      result
    end
    private_class_method :run_all

    sig { params(security: Security, secondary: Provider, result: T.untyped).void }
    def self.check_one(security, secondary, result)
      observed = secondary_closes(security, secondary)
      stored = Candle.daily
                     .where(security_id: security.id)
                     .where(date: WINDOW_DAYS.days.ago.to_date...Date.current)
                     .pluck(:date, :close).to_h
      # Only fully settled days both sources have; today is in-flight.
      comparable = (observed.keys & stored.keys).select { |d| d < Date.current }
      if comparable.empty?
        result.skipped += 1
        return
      end

      tolerance = crypto?(security) ? CRYPTO_TOLERANCE : EQUITY_TOLERANCE
      mismatches = comparable.filter_map do |date|
        stored_close = stored.fetch(date).to_d
        observed_close = T.must(observed[date]).to_d
        next if within_tolerance?(stored_close, observed_close, tolerance)

        Mismatch.new(date: date, stored: stored_close, observed: observed_close)
      end

      result.checked += 1
      if mismatches.any?
        result.mismatched += 1
        report!(security, secondary, mismatches)
      else
        result.clean += 1
        Issue.resolve!(issue_key(security))
      end
    end

    sig { params(stored: BigDecimal, observed: BigDecimal, tolerance: BigDecimal).returns(T::Boolean) }
    def self.within_tolerance?(stored, observed, tolerance)
      base = [ stored.abs, observed.abs ].max
      return stored == observed if base.zero?

      ((stored - observed).abs / base) <= tolerance
    end

    # date => close from the secondary provider, using its cheapest
    # read-only endpoint (spot-only providers have none and yield nothing).
    sig { params(security: Security, secondary: Provider).returns(T::Hash[Date, BigDecimal]) }
    def self.secondary_closes(security, secondary)
      provider = Router.provider_instance(secondary)
      return {} unless provider.respond_to?(:fetch_closes)

      provider.fetch_closes(security, from: WINDOW_DAYS.days.ago.to_date)
    end

    sig { params(security: Security, secondary: Provider, mismatches: T::Array[T.untyped]).void }
    def self.report!(security, secondary, mismatches)
      body = mismatches.first(5).map do |m|
        "#{m.date}: stored #{m.stored.to_f} vs #{secondary.serialize} #{m.observed.to_f}"
      end.join("\n")
      body += "\n(+#{mismatches.size - 5} more days)" if mismatches.size > 5

      # One batched load instead of a Household.find_by per audience member.
      household_ids = audience_household_ids(security)
      households = Household.where(id: household_ids).index_by(&:id)
      household_ids.each do |household_id|
        household = households[household_id] or next
        Current.set(household: household) do
          Issue.raise_once!(
            key: issue_key(security),
            title: "Price disagreement for #{security.ticker} (#{mismatches.size} of last #{WINDOW_DAYS} days)",
            body: body,
            source: ISSUE_SOURCE
          )
        end
      end
    end

    # Households that hold or watch the security — the ones whose numbers
    # the bad prices would distort.
    sig { params(security: Security).returns(T::Array[String]) }
    def self.audience_household_ids(security)
      holder_ids = Position.unscoped.where(security_id: security.id)
                           .where.not(quantity: 0).distinct.pluck(:household_id)
      watcher_ids = SecurityWatch.unscoped.where(security_id: security.id).distinct.pluck(:household_id)
      (holder_ids + watcher_ids).compact.uniq
    end

    sig { params(security: Security).returns(String) }
    def self.issue_key(security)
      "market_data.cross_check.#{security.id}"
    end

    sig { params(security: Security).returns(T::Boolean) }
    def self.crypto?(security)
      security.instrument_class == Instruments::InstrumentClass::Crypto
    end

    sig { params(provider: Provider).returns(Float) }
    def self.pace_for(provider)
      provider == Provider::CoinGecko ? 6.0 : 1.0
    end
    private_class_method :pace_for
  end
end
