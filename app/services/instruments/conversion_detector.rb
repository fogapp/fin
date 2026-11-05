# typed: strict

module Instruments
  # Finds instruments that became other instruments without the ledger
  # recording it — an unsponsored ADR swapped for a sponsored one, a CUSIP or
  # ticker change, a stock-for-stock merger — and proposes them as suggested
  # SecurityConversions for the user to confirm.
  #
  # The signature, per custodian-reported account (production's case was
  # SMNEY -> SMERY in Global on 2026-01-30):
  #
  # - A: the ledger still holds it (positive quantity, current units), the
  #   custodian no longer reports it, and its closes stopped — the old line
  #   stopped trading. A holding that still trades but has gone missing is a
  #   missing sell, not a conversion, and is left alone.
  # - B: the custodian reports more of it than the ledger explains (a
  #   positive anchor offset), and none of B's ledger activity predates A's
  #   last close — B's unexplained shares arrived when A left.
  #
  # Quantities are compared in each instrument's current units: ledger rows
  # are scaled by every share split after their trade date
  # (Positions::SplitAdjustment — spin-off price factors are not splits),
  # matching the split-adjusted closes they are priced with and the
  # valuation engine's own convention.
  # The ratio is B's unexplained shares per A share in those units — for
  # SMNEY -> SMERY 2910 / 582 = 5.0, a 1:1 exchange followed by SMERY's 5:1
  # split — snapped to a clean ratio when within RATIO_SNAP_TOLERANCE.
  #
  # A pair qualifies when the value carries across the switch (A's last
  # close x A's shares vs B's first close on/after the effective date x B's
  # unexplained shares, within VALUE_TOLERANCE), or — when either side has no
  # price to compare — when the two names share issuer words.
  class ConversionDetector
    extend T::Sig

    # A's closes must have stopped at least this long ago: a line that is
    # still trading hasn't been converted away.
    STOPPED_TRADING_DAYS = 14
    # An offset under this share of the custodian quantity is rounding, the
    # engine's own ANCHOR_TOLERANCE.
    OFFSET_TOLERANCE = T.let(BigDecimal("0.001"), BigDecimal)
    RATIO_SNAP_TOLERANCE = 0.02
    VALUE_TOLERANCE = 0.15
    # Denominators an exchange ratio is written with (1-for-1, 3-for-2,
    # 5-for-4 ...); the raw ratio snaps to the nearest such fraction.
    RATIO_DENOMINATORS = T.let((1..4).to_a.freeze, T::Array[Integer])
    # Words that say nothing about the issuer.
    NAME_NOISE = T.let(%w[
      a ag adr ads and asa co company corp corporation class common de each inc incorporated limited ltd
      n nv of ord ordinary pay date plc rep reg registered s sa se shs share shares sp spon sponsored
      the unsp unsponsored
    ].to_set.freeze, T::Set[String])

    Candidate = Struct.new(:from_security, :to_security, :account, :effective_date, :ratio, :evidence, :score,
                           keyword_init: true)

    sig { params(today: Date).void }
    def initialize(today: Date.current)
      @today = today
    end

    # Creates suggested conversions for new candidates. Pairs that already
    # have a conversion in any status — including dismissed — are skipped, so
    # a dismissal is permanent and nothing is duplicated.
    sig { returns(T::Array[SecurityConversion]) }
    def call
      known = SecurityConversion.pluck(:from_security_id, :to_security_id).to_set
      converted_from = SecurityConversion.where.not(status: SecurityConversion::Status::Dismissed.serialize)
                                         .pluck(:from_security_id).to_set

      candidates.filter_map do |c|
        from_id = c.from_security.id
        next if known.include?([ from_id, c.to_security.id ]) || converted_from.include?(from_id)

        converted_from << from_id
        SecurityConversion.create!(
          from_security: c.from_security, to_security: c.to_security,
          effective_date: c.effective_date, ratio: c.ratio,
          status: SecurityConversion::Status::Suggested, source: SecurityConversion::Source::Detected,
          evidence: c.evidence
        )
      end
    end

    # Best candidate per A (and at most one A per B), without writing.
    sig { returns(T::Array[Candidate]) }
    def candidates
      positions = Positions::CurrentPositions.new.relation.includes(:security, :account).to_a
                                             .reject { |s| s.source_row_hash.to_s.start_with?("computed:") }
      return [] if positions.empty?

      found = positions.group_by(&:account_id).flat_map do |_account_id, snaps|
        account_candidates(snaps)
      end

      taken = T.let(Set.new, T::Set[String])
      found.sort_by { |c| -c.score }.filter_map do |c|
        next if taken.include?(c.to_security.id) || taken.include?("from:#{c.from_security.id}")

        taken << c.to_security.id << "from:#{c.from_security.id}"
        c
      end
    end

    private

    sig { params(snaps: T::Array[PositionSnapshot]).returns(T::Array[Candidate]) }
    def account_candidates(snaps)
      account = T.must(T.must(snaps.first).account)
      reported = snaps.select { |s| s.quantity.to_d.positive? && s.security }
      reported_ids = reported.map(&:security_id).to_set

      ledger = ledger_rows(account.id)
      return [] if ledger.empty?

      splits = Positions::SplitAdjustment.splits_by_security((ledger.keys + reported_ids.to_a).uniq)
      holdings = ledger.to_h do |sid, rows|
        [ sid, rows.map { |date, qty| [ date, qty * Positions::SplitAdjustment.factor(splits[sid], date) ] } ]
      end

      from_ids = holdings.select { |sid, rows| !reported_ids.include?(sid) && rows.sum { |_, q| q }.positive? }.keys
      return [] if from_ids.empty?

      last_closes = MarketData::PriceSeries.edge_closes_by_security(from_ids)
      stopped = from_ids.select do |sid|
        last = last_closes[sid]
        last && last.first <= @today - STOPPED_TRADING_DAYS
      end
      return [] if stopped.empty?

      offsets = reported.filter_map do |snap|
        rows = holdings[snap.security_id] || []
        explained = rows.sum { |_, q| q }
        offset = snap.quantity.to_d - explained
        next unless offset > snap.quantity.to_d * OFFSET_TOLERANCE

        [ snap, offset, rows.map(&:first).min ]
      end
      return [] if offsets.empty?

      securities = Security.where(id: stopped).index_by(&:id)
      stopped.flat_map do |from_id|
        from = securities[from_id]
        next [] unless from

        last_date, last_close = T.must(last_closes[from_id])
        from_rows = holdings.fetch(from_id)
        from_qty = from_rows.select { |d, _| d <= last_date }.sum(BigDecimal("0")) { |_, q| q }
        next [] unless from_qty.positive?

        offsets.filter_map do |snap, offset, first_ledger|
          next if first_ledger && first_ledger <= last_date

          candidate(account, from, from_qty, last_date, last_close, snap, offset, first_ledger)
        end
      end
    end

    sig do
      params(account: Account, from: Security, from_qty: BigDecimal, last_date: Date, last_close: BigDecimal,
             snap: PositionSnapshot, offset: BigDecimal, first_ledger: T.nilable(Date)).returns(T.nilable(Candidate))
    end
    def candidate(account, from, from_qty, last_date, last_close, snap, offset, first_ledger)
      to = T.must(snap.security)
      first_close = MarketData::PriceSeries.edge_closes_by_security([ to.id ], on_or_after: last_date + 1)[to.id]
      effective = [ last_date + 1, first_close&.first ].compact.max
      effective = [ effective, first_ledger ].min if first_ledger

      raw_ratio = (offset / from_qty).to_f
      ratio, snapped = snap_ratio(raw_ratio)

      value_from = (from_qty * last_close).to_f
      value_to = first_close ? (offset * first_close.last).to_f : nil
      value_gap = value_to && value_from.positive? ? ((value_to - value_from).abs / value_from) : nil
      shared = shared_name_words(from, to)

      value_ok = value_gap && value_gap <= VALUE_TOLERANCE
      return nil unless value_ok || (value_gap.nil? && shared.any?)

      score = (value_gap ? 1.0 - value_gap : 0.5) + (shared.any? ? 0.5 : 0.0) + (snapped ? 0.25 : 0.0)
      Candidate.new(
        from_security: from, to_security: to, account: account, effective_date: effective,
        ratio: BigDecimal(ratio.to_s), score: score,
        evidence: {
          "account_id" => account.id, "account_name" => account.name,
          "from" => { "ticker" => from.ticker, "name" => from.name, "ledger_quantity" => from_qty.to_f,
                      "last_close_date" => last_date.iso8601, "last_close" => last_close.to_f },
          "to" => { "ticker" => to.ticker, "name" => to.name, "custodian_quantity" => snap.quantity.to_f,
                    "unexplained_quantity" => offset.to_f, "first_ledger_date" => first_ledger&.iso8601,
                    "first_close_date" => first_close&.first&.iso8601, "first_close" => first_close&.last&.to_f },
          "raw_ratio" => raw_ratio.round(6), "ratio_snapped" => snapped,
          "value_from" => value_from.round(2), "value_to" => value_to&.round(2),
          "value_gap_pct" => value_gap && (value_gap * 100).round(2),
          "shared_name_words" => shared
        }
      )
    end

    # {security_id => [[trade_date, signed quantity]]} for position-moving
    # ledger rows in one account.
    sig { params(account_id: String).returns(T::Hash[String, T::Array[[ Date, BigDecimal ]]]) }
    def ledger_rows(account_id)
      InvestmentTransaction
        .joins(:transaction_type)
        .where(account_id: account_id, transaction_types: { category: Positions::Rebuild::POSITION_CATEGORIES })
        .where.not(security_id: nil)
        .pluck(:security_id, :trade_date, :quantity, "transaction_types.category")
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(sid, date, qty, category), out|
          sign = Positions::Rebuild::INBOUND_CATEGORIES.include?(category) ? 1 : -1
          out[sid] << [ date, qty.to_d.abs * sign ]
        end
    end

    # [ratio, snapped?]: the nearest p/q (q <= 4) when within
    # RATIO_SNAP_TOLERANCE, else the raw ratio.
    sig { params(raw: Float).returns([ Float, T::Boolean ]) }
    def snap_ratio(raw)
      return [ raw, false ] unless raw.positive?

      best = RATIO_DENOMINATORS.filter_map do |q|
        p = (raw * q).round
        next if p.zero?

        clean = p.to_f / q
        [ clean, (raw - clean).abs / clean ]
      end.min_by(&:last)
      best && best.last <= RATIO_SNAP_TOLERANCE ? [ best.first, true ] : [ raw, false ]
    end

    sig { params(a: Security, b: Security).returns(T::Array[String]) }
    def shared_name_words(a, b)
      (name_words(a) & name_words(b)).sort
    end

    sig { params(security: Security).returns(T::Array[String]) }
    def name_words(security)
      security.name.to_s.downcase.split(/[^a-z]+/).reject { |w| w.size < 3 || NAME_NOISE.include?(w) }.uniq
    end
  end
end
