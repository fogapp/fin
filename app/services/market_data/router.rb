# typed: strict

module MarketData
  # Picks (and pins) exactly one provider per (instrument, capability) via
  # instrument_data_links. Defaults route by instrument class through an
  # ordered preference list — the first *available* (configured) provider
  # wins, so configuring Tiingo promotes it and deleting the integration
  # falls routing back to the next candidate. Links persist so health
  # tracking survives across runs; repin_defaults! re-evaluates them when an
  # integration is added or removed.
  module Router
    extend T::Sig

    # Ordered preference per capability and instrument class. Tiingo leads
    # for candles when configured: adjusted daily quality for equities, and
    # full OHLCV with deep history for crypto (keyless CoinGecko is
    # close-only, trailing year). The runner-up doubles as the cross-check
    # source (MarketData::CrossCheck).
    DEFAULTS = T.let({
      Capability::Candles => { Instruments::InstrumentClass::Crypto => [ Provider::Tiingo, Provider::CoinGecko ].freeze,
                               default: [ Provider::Tiingo, Provider::AlphaVantage ].freeze },
      Capability::Quotes  => { Instruments::InstrumentClass::Crypto => [ Provider::CoinMarketCap ].freeze,
                               default: [ Provider::AlphaVantage ].freeze },
      Capability::News => { default: [ Provider::AlphaVantage ].freeze },
      Capability::Metadata => { default: [ Provider::AlphaVantage ].freeze }
    }.freeze, T::Hash[Capability, T::Hash[T.untyped, T::Array[Provider]]])

    # Classes that have no sensible default provider for a capability.
    UNPRICEABLE_CLASSES = T.let({
      Capability::Candles => [ Instruments::InstrumentClass::CashEquivalent, Instruments::InstrumentClass::Fx,
                               Instruments::InstrumentClass::RealAsset, Instruments::InstrumentClass::Other,
                               Instruments::InstrumentClass::Bond ].freeze,
      Capability::Quotes => [ Instruments::InstrumentClass::CashEquivalent, Instruments::InstrumentClass::Fx,
                              Instruments::InstrumentClass::RealAsset, Instruments::InstrumentClass::Other,
                              Instruments::InstrumentClass::Bond ].freeze
    }.freeze, T::Hash[Capability, T::Array[Instruments::InstrumentClass]])

    sig { params(security: Security, capability: Capability).returns(T.nilable(InstrumentDataLink)) }
    def self.link_for(security, capability)
      resolve_link(security, capability, InstrumentDataLink.find_by(security_id: security.id, capability: capability))
    end

    # link_for over many instruments with one read for the existing links —
    # the scheduler walks every tiered instrument each run. Keyed by
    # security id.
    sig do
      params(securities: T::Array[Security], capability: Capability)
        .returns(T::Hash[String, T.nilable(InstrumentDataLink)])
    end
    def self.links_for(securities, capability)
      existing = InstrumentDataLink.where(security_id: securities.map(&:id), capability: capability)
                                   .index_by(&:security_id)
      securities.to_h { |security| [ security.id, resolve_link(security, capability, existing[security.id]) ] }
    end

    sig do
      params(security: Security, capability: Capability, existing: T.nilable(InstrumentDataLink))
        .returns(T.nilable(InstrumentDataLink))
    end
    def self.resolve_link(security, capability, existing)
      if existing
        # A pinned provider whose integration was deleted re-routes to the
        # current default rather than failing every sync.
        return existing if available?(T.unsafe(existing).provider)

        preferred = preferred_provider(security, capability)
        repin!(existing, preferred) if preferred && preferred != T.unsafe(existing).provider
        return existing
      end

      return nil if Array(UNPRICEABLE_CLASSES[capability]).include?(security.instrument_class)
      return nil if security.ticker.blank?

      provider = preferred_provider(security, capability)
      return nil if provider.nil?

      InstrumentDataLink.create!(security: security, capability: capability, provider: provider)
    rescue ActiveRecord::RecordNotUnique
      InstrumentDataLink.find_by(security_id: security.id, capability: capability)
    end
    private_class_method :resolve_link

    # First available candidate, falling back to the last candidate so an
    # entirely unconfigured deploy behaves like before (links pin to the
    # legacy default and surface auth errors through link health).
    sig { params(security: Security, capability: Capability).returns(T.nilable(Provider)) }
    def self.preferred_provider(security, capability)
      candidates = candidates_for(security, capability)
      return nil if candidates.empty?

      candidates.find { |provider| available?(provider) } || candidates.last
    end

    # Whether any configured provider can serve this instrument right now —
    # the gate for enqueueing an on-demand sync, without pinning a link.
    sig { params(security: Security, capability: Capability).returns(T::Boolean) }
    def self.available_for?(security, capability)
      return false if security.ticker.blank?
      return false if Array(UNPRICEABLE_CLASSES[capability]).include?(security.instrument_class)

      candidates_for(security, capability).any? { |provider| available?(provider) }
    end

    # The next available candidate after the pinned provider — the
    # independent source a cross-check compares against. nil when only one
    # configured provider covers the instrument.
    sig { params(security: Security, capability: Capability, primary: Provider).returns(T.nilable(Provider)) }
    def self.secondary_provider(security, capability, primary)
      candidates_for(security, capability)
        .find { |provider| provider != primary && available?(provider) }
    end

    sig { params(security: Security, capability: Capability).returns(T::Array[Provider]) }
    def self.candidates_for(security, capability)
      table = DEFAULTS[capability] or return []
      table[security.instrument_class] || table[:default] || []
    end

    # Whether a provider can currently authenticate. CoinGecko runs keyless.
    sig { params(provider: Provider).returns(T::Boolean) }
    def self.available?(provider)
      case provider
      when Provider::AlphaVantage   then ::AlphaVantage.configured?
      when Provider::CoinGecko      then true
      when Provider::CoinMarketCap  then ::CoinMarketCap.any_configured?
      when Provider::Tiingo         then ::Tiingo.configured?
      else T.absurd(provider)
      end
    end

    # Re-evaluates every link after an integration is added or removed. Pins
    # move only when the preferred provider actually changed; provider-
    # specific state (provider_ref, backoff, disabled) resets with the move.
    sig { void }
    def self.repin_defaults!
      InstrumentDataLink.find_each do |link|
        security = Security.unscoped.find_by(id: link.security_id) or next
        preferred = preferred_provider(security, T.unsafe(link).capability)
        next if preferred.nil? || preferred == T.unsafe(link).provider

        repin!(link, preferred)
      end
    end

    sig { params(link: InstrumentDataLink, provider: Provider).void }
    def self.repin!(link, provider)
      link.update!(provider: provider, provider_ref: nil, consecutive_failures: 0,
                   disabled: false, last_error: nil)
    end
    private_class_method :repin!

    sig { params(provider: Provider).returns(T.untyped) }
    def self.provider_instance(provider)
      case provider
      when Provider::AlphaVantage   then Providers::AlphaVantage.new
      when Provider::CoinGecko      then Providers::CoinGecko.new
      when Provider::CoinMarketCap  then Providers::CoinMarketCap.new
      when Provider::Tiingo         then Providers::Tiingo.new
      else T.absurd(provider)
      end
    end
  end
end
