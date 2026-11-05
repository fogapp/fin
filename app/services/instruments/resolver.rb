# typed: strict

module Instruments
  # THE way to find-or-create a Security. Every ingestion path (CSV
  # importers, Plaid, Coinbase, benchmarks, watch, restore) resolves through
  # here — previously nine call sites each had their own lookup semantics,
  # which is how BTC-the-coin and BTC-the-ETF ended up sharing rows and
  # price history.
  #
  # Resolution precedence: explicit identifiers (cusip, plaid_security_id,
  # coinbase_code, ...) then the class-appropriate symbol scheme (crypto
  # uses crypto_symbol; everything else uses ticker). A hit via a strong
  # identifier backfills weaker ones. A symbol hit whose stored cusip
  # disagrees with the caller's is a DIFFERENT instrument — we create a new
  # row and raise an Issue instead of adopting.
  module Resolver
    extend T::Sig

    # Identifier schemes checked before any symbol lookup, strongest first.
    STRONG_SCHEMES = T.let([
      InstrumentIdentifier::Scheme::Cusip,
      InstrumentIdentifier::Scheme::PlaidSecurityId,
      InstrumentIdentifier::Scheme::CoinbaseCode,
      InstrumentIdentifier::Scheme::Isin,
      InstrumentIdentifier::Scheme::Figi
    ].freeze, T::Array[InstrumentIdentifier::Scheme])

    sig do
      params(instrument_class: T.any(String, InstrumentClass), ticker: T.nilable(String),
             cusip: T.nilable(String),
             name: T.nilable(String), security_type: T.nilable(String),
             identifiers: T::Hash[T.any(String, Symbol), T.untyped],
             attributes: T::Hash[T.untyped, T.untyped]).returns(Security)
    end
    def self.resolve!(instrument_class:, ticker: nil, cusip: nil, name: nil,
                      security_type: nil, identifiers: {}, attributes: {})
      # Ingestion boundaries (syncers, importers) still pass raw strings —
      # deserialize here, keeping the old ArgumentError for unknown classes.
      klass = InstrumentClass.try_deserialize(instrument_class.to_s)
      raise ArgumentError, "unknown instrument_class #{instrument_class.inspect}" if klass.nil?

      ticker = normalize(ticker)
      cusip  = normalize(cusip)
      idents = identifiers.transform_keys(&:to_s).transform_values { |v| v.to_s.strip.presence }.compact

      # 1. Strong identifiers, in precedence order.
      lookup = { "cusip" => cusip }.merge(idents).compact
      STRONG_SCHEMES.each do |scheme|
        value = lookup[scheme.serialize]
        next if value.blank?

        if (found = find_by_identifier(scheme, value))
          winner = register!(found, symbol_scheme(klass) => ticker, "cusip" => cusip)
          backfill_attributes!(found, klass, cusip: winner.nil? ? cusip : nil)
          return found
        end
      end

      # 2. Class-appropriate symbol scheme.
      if ticker.present?
        found = find_by_identifier(symbol_scheme(klass), ticker)
        if found
          if cusip.present? && found.cusip.present? && found.cusip != cusip
            return conflict!(found, instrument_class: klass, ticker: ticker, cusip: cusip)
          else
            winner = register!(found, "cusip" => cusip, **lookup.slice("plaid_security_id", "coinbase_code"))
            backfill_attributes!(found, klass, cusip: winner.nil? ? cusip : nil)
            return found
          end
        end
      end

      create!(instrument_class: klass, ticker: ticker, cusip: cusip,
              name: name, security_type: security_type, lookup: lookup, attributes: attributes)
    end

    # Fills in what an existing row is missing from a later, better-informed
    # source. The cusip column only backfills when blank and the identifier
    # registered to this row (a strong-identifier hit used to register the
    # cusip identifier but leave the column empty). A row created as a
    # generic Equity/Other with no ticker — a CSV import's guess — takes a
    # source's explicit Bond classification (Plaid's "fixed income"); a
    # ticker-bearing row keeps its class, since a ticker makes it listed.
    sig { params(security: Security, klass: InstrumentClass, cusip: T.nilable(String)).void }
    def self.backfill_attributes!(security, klass, cusip:)
      updates = {}
      if cusip.present? && security.cusip.blank? && !Security.unscoped.where(cusip: cusip).where.not(id: security.id).exists?
        updates[:cusip] = cusip
      end
      if klass == InstrumentClass::Bond && security.ticker.blank? &&
         [ InstrumentClass::Equity, InstrumentClass::Other ].include?(security.instrument_class)
        updates[:instrument_class] = klass
        updates[:security_type] = legacy_type_for(klass)
      end
      security.update!(updates) if updates.any?
    end
    private_class_method :backfill_attributes!

    # Best-effort class from a custodian's free-form type string.
    sig { params(free_form: T.nilable(String)).returns(InstrumentClass) }
    def self.classify_free_form(free_form)
      key = free_form.to_s.downcase.strip
      return InstrumentClass::Other if key.blank?
      return InstrumentClass::Crypto         if key.include?("crypto")
      return InstrumentClass::Etf            if key.include?("etf") || key.include?("exchange traded")
      return InstrumentClass::Equity         if key.include?("stock") || key.include?("equity")
      return InstrumentClass::CashEquivalent if key.include?("cash")
      return InstrumentClass::Bond           if key.include?("bond") || key.include?("fixed")
      return InstrumentClass::MutualFund     if key.include?("fund")

      InstrumentClass::Other
    end

    PLAID_CLASS_MAP = T.let({
      "equity" => InstrumentClass::Equity, "etf" => InstrumentClass::Etf,
      "mutual fund" => InstrumentClass::MutualFund,
      "fixed income" => InstrumentClass::Bond, "cash" => InstrumentClass::CashEquivalent,
      "cryptocurrency" => InstrumentClass::Crypto, "derivative" => InstrumentClass::Option
    }.freeze, T::Hash[String, InstrumentClass])

    sig { params(plaid_type: T.nilable(String)).returns(InstrumentClass) }
    def self.classify_plaid(plaid_type)
      PLAID_CLASS_MAP.fetch(plaid_type.to_s, InstrumentClass::Other)
    end

    sig { params(scheme: InstrumentIdentifier::Scheme, value: String).returns(T.nilable(Security)) }
    def self.find_by_identifier(scheme, value)
      InstrumentIdentifier.find_by(scheme: scheme, value: value)&.security
    end

    sig { params(instrument_class: InstrumentClass).returns(InstrumentIdentifier::Scheme) }
    def self.symbol_scheme(instrument_class)
      if instrument_class == InstrumentClass::Crypto
        InstrumentIdentifier::Scheme::CryptoSymbol
      else
        InstrumentIdentifier::Scheme::Ticker
      end
    end

    # Registers each identifier for +security+. Returns the other Security an
    # identifier already belongs to (the "winner"), if any — either found
    # directly or after losing an insert race. Callers backfilling identifiers
    # onto an already-resolved row ignore the return value (conflicts surface
    # via resolution); create! uses it to dissolve a just-created duplicate.
    sig { params(security: Security, identifiers: T.untyped).returns(T.nilable(Security)) }
    def self.register!(security, identifiers)
      winner = T.let(nil, T.nilable(Security))
      identifiers.each do |scheme, value|
        value = value.to_s.strip
        next if value.blank?

        begin
          # Savepoint so a lost insert race doesn't poison an enclosing
          # transaction (create! wraps the whole create-and-register step).
          ident = InstrumentIdentifier.transaction(requires_new: true) do
            InstrumentIdentifier.find_or_create_by!(scheme: scheme.to_s, value: value) do |i|
              i.security = security
            end
          end
          winner ||= ident.security if ident.security_id != security.id
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          # A concurrent resolve registered this identifier first — re-look it
          # up so the caller can adopt the winning row. (An unknown scheme
          # fails the inclusion validation above and has no row to find.)
          scheme_enum = InstrumentIdentifier::Scheme.try_deserialize(scheme.to_s)
          existing = scheme_enum && find_by_identifier(scheme_enum, value)
          winner ||= existing if existing && existing.id != security.id
        end
      end
      winner
    end

    sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
    def self.normalize(value)
      value.to_s.upcase.strip.presence
    end

    sig do
      params(instrument_class: InstrumentClass, ticker: T.nilable(String), cusip: T.nilable(String),
             name: T.nilable(String), security_type: T.nilable(String),
             lookup: T::Hash[String, T.untyped], attributes: T::Hash[T.untyped, T.untyped],
             adopt_existing: T::Boolean).returns(Security)
    end
    def self.create!(instrument_class:, ticker:, cusip:, name:, security_type:, lookup:, attributes:, adopt_existing: true)
      result = T.let(nil, T.nilable(Security))
      Security.transaction do
        security = Security.create!(
          ticker:                ticker,
          cusip:                 cusip,
          name:                  name.presence,
          security_type:         security_type.presence || legacy_type_for(instrument_class),
          instrument_class:      instrument_class,
          instrument_attributes: attributes
        )
        winner = register!(security, lookup.merge(symbol_scheme(instrument_class) => ticker))
        # Lost a concurrent create race: an identifier we were about to claim
        # already points at another Security. Keep the winner and destroy the
        # identifier-less duplicate we just made, instead of letting it
        # fragment positions/prices the way the resolver exists to prevent.
        # (conflict! opts out — there the shared symbol identifier is known
        # and the second row is intentional.)
        if adopt_existing && winner
          security.destroy!
          result = winner
        else
          result = security
        end
      end
      T.must(result)
    end
    private_class_method :create!

    # Keeps the legacy security_type vocabulary populated during the
    # transition — several consumers still filter on it.
    LEGACY_TYPES = T.let({
      InstrumentClass::Equity => "Equity", InstrumentClass::Etf => "ETF",
      InstrumentClass::MutualFund => "Mutual Fund", InstrumentClass::Bond => "Fixed Income",
      InstrumentClass::CashEquivalent => "Cash", InstrumentClass::Crypto => Security::CRYPTO_TYPE
    }.freeze, T::Hash[InstrumentClass, String])

    sig { params(instrument_class: InstrumentClass).returns(T.nilable(String)) }
    def self.legacy_type_for(instrument_class)
      LEGACY_TYPES[instrument_class]
    end
    private_class_method :legacy_type_for

    sig { params(found: Security, instrument_class: InstrumentClass, ticker: String, cusip: String).returns(Security) }
    def self.conflict!(found, instrument_class:, ticker:, cusip:)
      security = create!(instrument_class: instrument_class, ticker: ticker, cusip: cusip,
                         name: nil, security_type: nil, lookup: { "cusip" => cusip }, attributes: {},
                         adopt_existing: false)
      Issue.raise_once!(
        key:      "instrument_conflict:#{instrument_class}:#{ticker}:#{cusip}",
        title:    "Two instruments share ticker #{ticker}",
        body:     "An instrument with ticker #{ticker} already exists (#{found.display_name}, cusip #{found.cusip}) " \
                  "but a source supplied cusip #{cusip}. A separate instrument was created — review and merge if wrong.",
        severity: Severity::Warning,
        source:   "instrument_resolver"
      )
      security
    end
    private_class_method :conflict!
  end
end
