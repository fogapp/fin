# typed: strict

module RealEstate
  # Refreshes one property from RentCast. The only thing that writes
  # RentCast-sourced valuations.
  #
  # Two calls at most, and usually one:
  #
  #   1. GET /properties — only when the facts cache is missing or older
  #      than FACTS_TTL. Fills the facts columns and seeds years of chart
  #      data in a single request: one TaxAssessment valuation per assessed
  #      year, one Sale valuation per recorded deed event.
  #   2. GET /avm/value — every run. One market-value point for today.
  #
  # Facts run first so the canonical address is known before the AVM lookup;
  # an ambiguous address resolves more reliably that way.
  class PropertyRefresher
    extend T::Sig

    sig { params(property: RealEstateProperty, client: T.nilable(Rentcast::Client), force_facts: T::Boolean).void }
    def initialize(property, client: nil, force_facts: false)
      @property    = property
      @client      = T.let(client || Rentcast::Client.new, Rentcast::Client)
      @force_facts = force_facts
    end

    sig { returns(RealEstateProperty) }
    def call
      refresh_facts if @force_facts || facts_stale?
      refresh_value

      @property.update!(last_synced_at: Time.current, last_sync_error: nil)
      Issue.resolve!(issue_key)
      @property
    rescue Rentcast::Client::NotFound => e
      # RentCast simply doesn't cover this address. Retrying weekly would
      # burn quota forever, so drop it to manual and say so.
      @property.update!(sync_enabled: false, last_sync_error: e.message)
      raise_issue("RentCast can't find #{@property.name}",
                  "#{e.message} Automatic valuation is off for this property — enter values manually.")
      @property
    rescue Rentcast::Client::Error, RentcastConfiguration::QuotaExceeded => e
      @property.update!(last_sync_error: e.message)
      raise_issue("RentCast sync failed for #{@property.name}", e.message)
      raise
    end

    private

    sig { returns(T::Boolean) }
    def facts_stale?
      synced = @property.facts_synced_at
      synced.nil? || synced < RealEstateProperty::FACTS_TTL.ago
    end

    sig { void }
    def refresh_facts
      record = @client.property_record(@property.query_address)

      @property.update!(
        formatted_address: record["formattedAddress"].presence || @property.formatted_address,
        rentcast_id:       record["id"].presence || @property.rentcast_id,
        city:              @property.city.presence      || record["city"],
        state:             @property.state.presence     || record["state"],
        zip_code:          @property.zip_code.presence  || record["zipCode"],
        latitude:          record["latitude"],
        longitude:         record["longitude"],
        property_type:     record["propertyType"],
        bedrooms:          record["bedrooms"],
        bathrooms:         record["bathrooms"],
        square_footage:    record["squareFootage"],
        lot_size:          record["lotSize"],
        year_built:        record["yearBuilt"],
        hoa_fee:           record.dig("hoa", "fee"),
        facts_synced_at:   Time.current
      )

      seed_tax_assessments(record["taxAssessments"])
      seed_sales(record)
    rescue Rentcast::Client::NotFound
      # The record lookup missing isn't fatal — the AVM endpoint resolves
      # addresses independently and may still return an estimate. Stamp the
      # cache so a permanently unmatched address doesn't retry every week.
      @property.update!(facts_synced_at: Time.current)
    end

    sig { void }
    def refresh_value
      estimate = @client.value_estimate(@property.query_address)
      price    = estimate["price"]
      raise Rentcast::Client::NotFound, "RentCast returned no value estimate" if price.blank?

      @property.record_valuation!(
        source:     RealEstateValuation::Source::Rentcast,
        as_of:      Date.current,
        amount:     price,
        value_low:  estimate["priceRangeLow"],
        value_high: estimate["priceRangeHigh"],
        payload:    { "comparables_count" => Array(estimate["comparables"]).size }
      )

      backfill_facts_from(estimate["subjectProperty"])
    end

    # The AVM response carries the same subject-property fields as a record
    # lookup, so a property whose /properties call failed still gets facts
    # for free.
    sig { params(subject: T.untyped).void }
    def backfill_facts_from(subject)
      return if subject.blank?

      attrs = {
        property_type:  @property.property_type.presence   || subject["propertyType"],
        bedrooms:       @property.bedrooms                 || subject["bedrooms"],
        bathrooms:      @property.bathrooms                || subject["bathrooms"],
        square_footage: @property.square_footage           || subject["squareFootage"],
        lot_size:       @property.lot_size                 || subject["lotSize"],
        year_built:     @property.year_built               || subject["yearBuilt"],
        latitude:       @property.latitude                 || subject["latitude"],
        longitude:      @property.longitude                || subject["longitude"]
      }.compact

      @property.update!(attrs) if attrs.any?
    end

    # taxAssessments is a year-keyed map: {"2024" => {year:, value:, ...}}.
    # Each becomes a point dated Dec 31 of its year — assessments describe a
    # whole tax year, and year-end keeps them from jostling with the AVM
    # points that arrive weekly.
    sig { params(assessments: T.untyped).void }
    def seed_tax_assessments(assessments)
      return if assessments.blank?

      T.cast(assessments, T::Hash[String, T.untyped]).each_value do |entry|
        year  = entry["year"] || entry[:year]
        value = entry["value"] || entry[:value]
        next if year.blank? || value.blank? || value.to_d.zero?

        @property.record_valuation!(
          source:  RealEstateValuation::Source::TaxAssessment,
          as_of:   Date.new(year.to_i, 12, 31),
          amount:  value,
          payload: entry
        )
      end
    end

    # history is a date-keyed map of events; only sales carry a price worth
    # charting. lastSalePrice is included in case it predates the history
    # window.
    sig { params(record: T::Hash[String, T.untyped]).void }
    def seed_sales(record)
      events = T.cast(record["history"] || {}, T::Hash[String, T.untyped]).values
      events.each do |event|
        next unless event["event"].to_s.casecmp("sale").zero?

        price = event["price"]
        date  = parse_date(event["date"])
        next if price.blank? || date.nil? || price.to_d.zero?

        @property.record_valuation!(
          source: RealEstateValuation::Source::Sale, as_of: date, amount: price, payload: event
        )
      end

      last_price = record["lastSalePrice"]
      last_date  = parse_date(record["lastSaleDate"])
      return if last_price.blank? || last_date.nil? || last_price.to_d.zero?

      @property.record_valuation!(
        source: RealEstateValuation::Source::Sale, as_of: last_date, amount: last_price
      )
    end

    sig { params(value: T.untyped).returns(T.nilable(Date)) }
    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    sig { returns(String) }
    def issue_key = "rentcast_property_#{@property.id}"

    sig { params(title: String, body: String).void }
    def raise_issue(title, body)
      Issue.raise_once!(key: issue_key, title: title, body: body, severity: Severity::Warning, source: "rentcast")
    end
  end
end
