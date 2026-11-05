# typed: strict

module Valuation
  # Honest portfolio valuation over time: ledger-derived daily quantities ×
  # adjusted daily closes, per (account, instrument), anchored to what the
  # custodians report. The rules, in the order they apply:
  #
  # 1. Units. Ledger quantities are converted to current share units by
  #    every genuine split after the trade (Positions::SplitAdjustment), the
  #    units adjusted closes and custodian snapshots use. Spin-off price
  #    adjustments that providers file as "splits" don't touch quantities.
  # 2. Conversions. A confirmed SecurityConversion moves each account's
  #    shares from the old instrument to the new one on its effective date
  #    (apply_conversions!), so the two are never counted together.
  # 3. Anchoring. A holding the custodian reports is its ledger plus a
  #    constant offset matching the report (anchor_to_snapshot). A holding
  #    it no longer reports, in an account it reports on, settles at the
  #    custodian's zero (settle_at_exit): shares the ledger still shows are
  #    closed out at the exit; sales the ledger has no purchases for are
  #    carried back as held until sold.
  # 4. Prices. A reported holding keeps its last close however old (the
  #    snapshot price before any close); any other holding's close values
  #    it for STALE_CLOSE_DAYS. Bonds quoted per 100 are scaled to dollars.
  # 5. Window independence. A date's value never depends on the query's
  #    from/to — every look-back is fixed per day.
  # 6. Flows. Value the engine adds or removes without a ledger trade
  #    (exits, stale drop-outs, first prices) is reported by
  #    call_with_flows so performance can treat it as external.
  #
  # Replaces the snapshot-sum approach whose Plaid rows rewrote history and
  # whose unadjusted prices drew split cliffs.
  module PortfolioSeries
    extend T::Sig

    # Household (or account_ids-narrowed) daily totals: the per-account
    # series summed. This used to be a separate, un-anchored ledger walk —
    # ledger quantities × closes with no custodian anchor — which valued the
    # production household at ~$1.2M against ~$11.3M, because most holdings'
    # ledgers are incomplete (transfers-in, pre-sync history). One engine now
    # serves the Portfolio page, performance and net worth alike.
    #
    # Returns {"YYYY-MM-DD" => Float}; days after a full sale carry 0.0.
    sig { params(from: Date, to: Date, account_ids: T.nilable(T::Array[String])).returns(T::Hash[String, Float]) }
    def self.call(from:, to: Date.current, account_ids: nil)
      sum_by_date(call_by_account(from: from, to: to, account_ids: account_ids))
        .sort.to_h { |date, v| [ date.to_s, v.round(2).to_f ] }
    end

    # The household series (as #call) plus the value the engine itself added
    # or removed on each day without a ledger trade behind it — a custodian
    # exit closing out a holding the ledger still shows, a ledger-only
    # holding dropping out when its closes go stale (or returning when one
    # reappears), a holding first gaining a price mid-window. Performance
    # treats these as external flows, so a drop-out isn't read as a loss.
    # Signed like ledger flows: value added positive, removed negative.
    # Conversions move value between instruments and produce no flow.
    #
    # Returns {values: {"YYYY-MM-DD" => Float}, flows: {Date => Float}}.
    sig do
      params(from: Date, to: Date, account_ids: T.nilable(T::Array[String]))
        .returns({ values: T::Hash[String, Float], flows: T::Hash[Date, Float] })
    end
    def self.call_with_flows(from:, to: Date.current, account_ids: nil)
      result = compute(from: from, to: to, account_ids: account_ids)
      {
        values: sum_by_date(result.by_account).sort.to_h { |date, v| [ date.to_s, v.round(2).to_f ] },
        flows:  sum_by_date(result.flows_by_account).reject { |_, v| v.abs < 0.005 }.transform_values { |v| v.round(2).to_f }
      }
    end

    sig { params(series_by_key: T::Hash[String, T::Hash[Date, Float]]).returns(T::Hash[Date, Float]) }
    def self.sum_by_date(series_by_key)
      totals = T.let(Hash.new(0.0), T::Hash[Date, Float])
      series_by_key.each_value do |series|
        series.each { |date, value| totals[date] = totals.fetch(date, 0.0) + value }
      end
      totals
    end
    private_class_method :sum_by_date

    # Per-account daily values, anchored to what the custodians last
    # reported. Each current position (account, instrument) is valued as its
    # ledger quantity plus a constant offset that makes the ledger agree with
    # the snapshot on the snapshot's date:
    #
    # - A complete ledger has no offset, so this is exactly the ledger walk.
    # - An incomplete one (transfers-in, pre-sync history, a split the ledger
    #   never recorded) is carried back from the reported quantity instead of
    #   dropping out or charting a cliff.
    # - A position with no ledger at all is held flat at the observation.
    #
    # Instruments no current position mentions (sold out, manual accounts)
    # are valued straight off the ledger, attributed to their own account.
    # A ledger pair whose instrument IS covered by a position on another
    # account is left out: custodian rows and ledger rows for one holding
    # often sit on different account rows, and counting both would double
    # it. In an account a custodian reports on, a ledger-only holding is
    # closed out where the custodian stopped seeing it — see custodian_exits
    # (an ADR converted in January, never recorded as a disposal, otherwise
    # kept its 582 shares at the last pre-conversion close for eight months).
    #
    # Prices: a reported position is valued at its last close however old
    # (the snapshot price only before any close exists); a ledger-only
    # holding's close values it for STALE_CLOSE_DAYS and no longer (see
    # add_valued_series!). The same rule
    # makes a date's value independent of the window around it — each day's
    # price comes from a fixed look-back, never from however far back the
    # query happened to start.
    #
    # Face-value instruments (bonds quoted per 100) are scaled back to
    # dollars — see price_scale.
    #
    # Everything is resolved in bulk (a handful of grouped queries, not one
    # per holding), and every account's series is dense from its first value
    # through `to` (0.0 while nothing is held), so a carry-forward reader
    # never extends a sold position's last value.
    #
    # Returns {account_id => {Date => Float}}.
    sig do
      params(from: Date, to: Date, account_ids: T.nilable(T::Array[String]))
        .returns(T::Hash[String, T::Hash[Date, Float]])
    end
    def self.call_by_account(from:, to: Date.current, account_ids: nil)
      compute(from: from, to: to, account_ids: account_ids).by_account
    end

    Result = Struct.new(:by_account, :flows_by_account, keyword_init: true)

    # One holding to value: [account_id, security_id, quantities, fallback
    # price, scale, reported, dates whose quantity change the engine made up]
    Holding = T.type_alias do
      [ String, String, T::Hash[Date, BigDecimal], T.nilable(BigDecimal), Float, T::Boolean, T::Set[Date] ]
    end

    sig { params(from: Date, to: Date, account_ids: T.nilable(T::Array[String])).returns(Result) }
    def self.compute(from:, to:, account_ids:)
      all_positions = Positions::CurrentPositions.new.relation.includes(:security).to_a
      covered_security_ids = all_positions.map(&:security_id).to_set
      positions = all_positions.select { |snap| snap.security && (account_ids.nil? || account_ids.include?(snap.account_id)) }
      conversions = SecurityConversion.confirmed.order(:effective_date, :created_at).to_a

      ledger_only = ledger_pairs(account_ids).reject { |_, security_id| covered_security_ids.include?(security_id) }
      anchored    = positions.map { |snap| [ snap.account_id, snap.security_id ] }
      converted   = conversion_pairs((anchored + ledger_only).uniq, conversions)
      # Anchoring compares the ledger with each snapshot on the snapshot's own
      # date, so the ledger is replayed through the newest snapshot even when
      # the window ends earlier — truncated at `to`, a window ending before
      # the snapshot computed every offset against the wrong ledger total.
      ledger_through = [ to, *all_positions.map(&:as_of_date) ].max
      quantities_by_pair = daily_quantities_by_pair((anchored + ledger_only + converted).uniq, ledger_through)
      apply_conversions!(quantities_by_pair, conversions, all_positions.index_by { |s| [ s.account_id, s.security_id ] })
      # A conversion can land an instrument in an account whose ledger never
      # held it; value it there unless a custodian row covers it.
      anchored_set = anchored.to_set
      ledger_only |= converted.reject do |pair|
        anchored_set.include?(pair) || covered_security_ids.include?(pair.last) || !quantities_by_pair.key?(pair)
      end
      exits  = custodian_exits(all_positions, ledger_only, quantities_by_pair)
      scales = ledger_only_scales(ledger_only.map(&:last).uniq)

      holdings = T.let([], T::Array[Holding])
      positions.each do |snap|
        ledger = quantities_by_pair[[ snap.account_id, snap.security_id ]] || {}
        quantities = anchor_to_snapshot(ledger, snap, from)
        next if quantities.empty?

        fallback = snap.price.present? && snap.price.to_d.positive? ? snap.price.to_d : nil
        holdings << [ snap.account_id, snap.security_id, quantities, fallback, price_scale(snap), true, Set.new ]
      end
      ledger_only.each do |account_id, security_id|
        quantities = quantities_by_pair[[ account_id, security_id ]]
        next if quantities.nil? || quantities.empty?

        synthetic = T.let(Set.new, T::Set[Date])
        exit_date = exits[[ account_id, security_id ]]
        quantities, synthetic = settle_at_exit(quantities, exit_date, from) if exit_date
        holdings << [ account_id, security_id, quantities, nil, scales.fetch(security_id, 1.0), false, synthetic ]
      end

      # Each instrument's closes from STALE_CLOSE_DAYS before the first day
      # it's valued — exactly the look-back add_valued_series! honours, so a
      # longer fetch could never change a value.
      windows = T.let({}, T::Hash[String, Date])
      holdings.each do |_account_id, security_id, quantities, *|
        earliest = [ T.must(quantities.keys.min), from ].max - STALE_CLOSE_DAYS
        current = windows[security_id]
        windows[security_id] = current.nil? || earliest < current ? earliest : current
      end
      closes_by_security = MarketData::PriceSeries.daily_closes_by_security(windows, to: to)
      # A reported position carries its last close however old (see
      # add_valued_series!), so each window also gets the close just before
      # it — without it, a date's price would depend on how far back the
      # query happened to start.
      MarketData::PriceSeries.closes_before_by_security(windows).each do |security_id, (date, close)|
        (closes_by_security[security_id] ||= {})[date] ||= close
      end

      by_account = T.let(
        Hash.new { |h, k| h[k] = Hash.new(0.0) },
        T::Hash[String, T::Hash[Date, Float]]
      )
      flows_by_account = T.let(
        Hash.new { |h, k| h[k] = Hash.new(0.0) },
        T::Hash[String, T::Hash[Date, Float]]
      )
      holdings.each do |account_id, security_id, quantities, fallback, scale, reported, synthetic|
        add_valued_series!(
          T.must(by_account[account_id]), quantities, closes_by_security[security_id] || {}, from, to,
          fallback_price: fallback, scale: scale, reported: reported,
          flows: T.must(flows_by_account[account_id]), synthetic_dates: synthetic
        )
      end

      dense = by_account.transform_values do |series|
        next {} if series.empty?

        (T.must(series.keys.min)..to).to_h { |date| [ date, series.fetch(date, 0.0).round(2).to_f ] }
      end.reject { |_, series| series.empty? }
      Result.new(by_account: dense, flows_by_account: flows_by_account.to_h)
    end
    private_class_method :compute

    # Ledger quantities shifted so they equal the snapshot's quantity on the
    # snapshot's date. Offsets under ANCHOR_TOLERANCE of the position are
    # rounding (fractional-share dust, lot rounding), not missing history,
    # and leave the ledger as is.
    ANCHOR_TOLERANCE = 0.001

    # How long a close keeps valuing a holding. Long enough for anything
    # legitimately priced monthly (NAV funds, custodian-priced private
    # holdings), sparse history, holidays and a price sync that missed a
    # stretch of nights; short enough that an instrument whose prices simply
    # stop — delisted, converted, merged away — stops being valued within
    # about six weeks instead of forever at its final close.
    STALE_CLOSE_DAYS = 45

    COMPUTED_PREFIX = "computed:"

    sig do
      params(ledger: T::Hash[Date, BigDecimal], snap: PositionSnapshot, from: Date)
        .returns(T::Hash[Date, BigDecimal])
    end
    def self.anchor_to_snapshot(ledger, snap, from)
      observed  = snap.quantity.to_d
      as_of     = snap.as_of_date
      ledger_at = ledger.select { |d, _| d <= as_of }.max_by(&:first)&.last || BigDecimal("0")
      offset    = observed - ledger_at
      return ledger if !ledger.empty? && offset.abs <= observed.abs * ANCHOR_TOLERANCE

      # Before the ledger's first entry the holding was just the offset
      # (what the custodian says was there that the ledger never saw).
      seed = [ from, as_of, *ledger.keys.min ].min
      { seed => offset }.merge(ledger.transform_values { |q| q + offset })
    end
    private_class_method :anchor_to_snapshot

    # Where a custodian says a ledger-only holding ended. The holding's
    # account is custodian-reported (it has a non-computed current position),
    # yet no current position covers the instrument, so the custodian's
    # answer today is zero. When it went to zero:
    #
    # - If the custodian reported the pair before, the day after its last
    #   report (a row it stopped refreshing, or zero-stamped).
    # - If it never did, by the custodian's first observation of the account
    #   — nothing reported means nothing was there.
    #
    # Either date only stands if the ledger agrees nothing happened since: a
    # trade on or after it means the holding was live while the custodian
    # was watching, so the only certain zero is the latest report. Ledger
    # history before the exit is untouched — it still shows what was held.
    #
    # Accounts without custodian rows (manual, computed-only) never get an
    # exit: their ledger is the only record there is.
    sig do
      params(all_positions: T::Array[PositionSnapshot], ledger_only: T::Array[[ String, String ]],
             quantities_by_pair: T::Hash[[ String, String ], T::Hash[Date, BigDecimal]])
        .returns(T::Hash[[ String, String ], Date])
    end
    def self.custodian_exits(all_positions, ledger_only, quantities_by_pair)
      latest_report = all_positions
        .reject { |snap| snap.source_row_hash.to_s.start_with?(COMPUTED_PREFIX) }
        .group_by(&:account_id)
        .transform_values { |snaps| snaps.map(&:as_of_date).max }
      account_ids = ledger_only.map(&:first).uniq & latest_report.keys
      return {} if account_ids.empty?

      custodian = PositionSnapshot.where(account_id: account_ids)
                                  .where.not(Positions::CurrentPositions::COMPUTED_PREFIX_SQL)
      first_report  = custodian.group(:account_id).minimum(:as_of_date)
      last_reported = custodian.where(security_id: ledger_only.map(&:last).uniq)
                               .group(:account_id, :security_id).maximum(:as_of_date)

      ledger_only.each_with_object({}) do |(account_id, security_id), exits|
        latest = latest_report[account_id]
        quantities = quantities_by_pair[[ account_id, security_id ]]
        next if latest.nil? || quantities.nil? || quantities.empty?

        reported  = last_reported[[ account_id, security_id ]]
        candidate = reported ? reported + 1 : first_report.fetch(account_id, latest)
        exits[[ account_id, security_id ]] =
          T.must(quantities.keys.max) < candidate ? [ candidate, latest ].min : latest
      end
    end
    private_class_method :custodian_exits

    # What a ledger-only holding in a custodian account looks like given the
    # custodian says it was gone by exit_date. The ledger's quantity just
    # before the exit decides what the gap means:
    #
    # - Positive: shares the ledger never saw leave — an unrecorded disposal
    #   (SMNEY's January ADR conversion). The ledger stands up to the exit
    #   and the holding closes out there; that exit is the engine's doing,
    #   so it's returned as a synthetic date (a flow, not a loss).
    # - Negative: sales with no recorded purchases — shares bought before
    #   the ledger began (a direct-indexing account's tax-lot harvesting).
    #   Anchor to the custodian's zero instead: the missing shares are
    #   carried back to the start, so what was later sold counts as held
    #   until the sale.
    # - Near zero: the ledger already agrees; close out without a flow.
    #
    # Returns [quantities, synthetic change dates].
    sig do
      params(quantities: T::Hash[Date, BigDecimal], exit_date: Date, from: Date)
        .returns([ T::Hash[Date, BigDecimal], T::Set[Date] ])
    end
    def self.settle_at_exit(quantities, exit_date, from)
      before = quantities.reject { |date, _| date >= exit_date }
      at_exit = before.max_by(&:first)&.last || BigDecimal("0")
      peak = quantities.values.map(&:abs).max || BigDecimal("0")

      if at_exit.negative? && at_exit.abs > peak * ANCHOR_TOLERANCE
        offset = -at_exit
        seed = [ from, *before.keys.min ].min
        [ { seed => offset }.merge(before.transform_values { |q| q + offset }).merge(exit_date => BigDecimal("0")), Set.new ]
      else
        synthetic = at_exit.positive? && at_exit > peak * ANCHOR_TOLERANCE ? Set[exit_date] : Set.new
        [ before.merge(exit_date => BigDecimal("0")), synthetic ]
      end
    end
    private_class_method :settle_at_exit

    # Pairs a confirmed conversion can reach: every account that holds (or
    # had) the from-instrument gets the to-instrument too, transitively, so
    # the ledger load below covers A -> B -> C chains.
    sig do
      params(pairs: T::Array[[ String, String ]], conversions: T::Array[SecurityConversion])
        .returns(T::Array[[ String, String ]])
    end
    def self.conversion_pairs(pairs, conversions)
      return [] if conversions.empty?

      reached = pairs.to_set
      added = T.let([], T::Array[[ String, String ]])
      loop do
        fresh = conversions.flat_map do |c|
          reached.select { |_, security_id| security_id == c.from_security_id }
                 .map { |account_id, _| [ account_id, c.to_security_id ] }
        end.reject { |pair| reached.include?(pair) }
        break if fresh.empty?

        fresh.each { |pair| reached << pair }
        added.concat(fresh)
      end
      added.uniq
    end
    private_class_method :conversion_pairs

    # Confirmed conversions replayed as same-day transfers, in date order
    # (so chains compose): in each account, whatever the from-instrument
    # held on effective_date leaves and ratio times it arrives in the
    # to-instrument, in current units. The to-instrument's anchor then sees
    # the shares arrive on the day they did, instead of carrying them back
    # to the start while the old instrument is still counted.
    #
    # An account whose custodian still reports the from-instrument on or
    # after the conversion date is left alone — the custodian outranks a
    # conversion record for that account. A from-instrument the custodian
    # last reported before the conversion is taken at its anchored quantity,
    # so a holding with no ledger at all still converts.
    sig do
      params(quantities_by_pair: T::Hash[[ String, String ], T::Hash[Date, BigDecimal]],
             conversions: T::Array[SecurityConversion],
             positions_by_pair: T::Hash[[ String, String ], PositionSnapshot]).void
    end
    def self.apply_conversions!(quantities_by_pair, conversions, positions_by_pair)
      conversions.each do |conversion|
        day = conversion.effective_date
        account_ids = (quantities_by_pair.keys + positions_by_pair.keys)
          .select { |_, security_id| security_id == conversion.from_security_id }.map(&:first).uniq

        account_ids.each do |account_id|
          from_pair = [ account_id, conversion.from_security_id ]
          snap = positions_by_pair[from_pair]
          next if snap && snap.as_of_date >= day && snap.quantity.to_d.positive?

          base = quantities_by_pair[from_pair] || {}
          held = quantity_on(snap ? anchor_to_snapshot(base, snap, day) : base, day)
          next unless held.positive?

          to_pair = [ account_id, conversion.to_security_id ]
          quantities_by_pair[from_pair] = shift_from(base, day, -held)
          quantities_by_pair[to_pair] = shift_from(quantities_by_pair[to_pair] || {}, day, held * conversion.ratio.to_d)
        end
      end
    end
    private_class_method :apply_conversions!

    sig { params(quantities: T::Hash[Date, BigDecimal], date: Date).returns(BigDecimal) }
    def self.quantity_on(quantities, date)
      quantities.select { |d, _| d <= date }.max_by(&:first)&.last || BigDecimal("0")
    end
    private_class_method :quantity_on

    # quantities with delta added from date onward (a change dated `date`).
    sig do
      params(quantities: T::Hash[Date, BigDecimal], date: Date, delta: BigDecimal)
        .returns(T::Hash[Date, BigDecimal])
    end
    def self.shift_from(quantities, date, delta)
      shifted = quantities.to_h { |d, q| [ d, d >= date ? q + delta : q ] }
      shifted[date] = quantity_on(quantities, date) + delta
      shifted.sort.to_h
    end
    private_class_method :shift_from

    # Per-100-of-face quoting (bonds) — see Positions::PriceScale. Closes,
    # custodian closes and the snapshot fallback are all stored as quoted, so
    # the scale is applied once, in add_valued_series!.
    sig { params(snap: PositionSnapshot).returns(Float) }
    def self.price_scale(snap)
      Positions::PriceScale.for(snap)
    end
    private_class_method :price_scale

    # Quoting scale for ledger-only instruments, which have no current
    # snapshot: the ratio on each one's newest priced snapshot in any
    # account, else the convention remembered on the security — a sold
    # bond's ledger face amount still needs its per-100 closes scaled.
    sig { params(security_ids: T::Array[String]).returns(T::Hash[String, Float]) }
    def self.ledger_only_scales(security_ids)
      return {} if security_ids.empty?

      scales = PositionSnapshot.where(security_id: security_ids)
        .where("quantity <> 0 AND price > 0 AND market_value > 0")
        .select("DISTINCT ON (security_id) id, security_id, quantity, price, market_value")
        .order(:security_id, as_of_date: :desc)
        .to_h do |snap|
          ratio = Positions::PriceScale.from_ratio(quantity: snap.quantity, price: snap.price, market_value: snap.market_value)
          [ snap.security_id, ratio || 1.0 ]
        end
      Security.where(id: security_ids - scales.keys).select(&:quoted_per_hundred?).each do |security|
        scales[security.id] = Positions::PriceScale::PER_HUNDRED
      end
      scales
    end
    private_class_method :ledger_only_scales

    # Cumulative signed quantity per day from the transaction ledger, for every
    # (account, instrument) pair at once, in each instrument's current share
    # units (see Positions::SplitAdjustment) — the units adjusted closes and
    # custodian snapshots use. Keyed [account_id, security_id].
    sig do
      params(pairs: T::Array[[ String, String ]], to: Date)
        .returns(T::Hash[[ String, String ], T::Hash[Date, BigDecimal]])
    end
    def self.daily_quantities_by_pair(pairs, to)
      return {} if pairs.empty?

      deltas = InvestmentTransaction
        .joins(:transaction_type)
        .where(account_id: pairs.map(&:first).uniq, security_id: pairs.map(&:last).uniq,
               transaction_types: { category: Positions::Rebuild::POSITION_CATEGORIES })
        .where(trade_date: ..to)
        .group(:account_id, :security_id, :trade_date, "transaction_types.category")
        .sum(:quantity)

      # Regroup into per-pair {[date, category] => qty} before replaying, so
      # the running total below is identical to the per-pair version.
      by_pair = T.let(
        Hash.new { |h, k| h[k] = {} },
        T::Hash[[ String, String ], T::Hash[[ Date, String ], T.untyped]]
      )
      deltas.each do |(account_id, security_id, date, category), qty|
        T.must(by_pair[[ account_id, security_id ]])[[ date, category ]] = qty
      end
      splits = Positions::SplitAdjustment.splits_by_security(pairs.map(&:last).uniq)

      by_pair.to_h do |(account_id, security_id), pair_deltas|
        running = T.let(BigDecimal("0"), BigDecimal)
        by_date = T.let({}, T::Hash[Date, BigDecimal])
        pair_deltas.keys.map(&:first).uniq.sort.each do |date|
          bought = Positions::Rebuild::INBOUND_CATEGORIES.sum(BigDecimal("0")) { |c| pair_deltas[[ date, c ]].to_d.abs }
          sold   = Positions::Rebuild::OUTBOUND_CATEGORIES.sum(BigDecimal("0")) { |c| pair_deltas[[ date, c ]].to_d.abs }
          running += (bought - sold) * Positions::SplitAdjustment.factor(splits[security_id], date)
          by_date[date] = running
        end
        [ [ account_id, security_id ], by_date ]
      end
    end
    private_class_method :daily_quantities_by_pair

    # Adds quantity × price to series for each day in [max(first change,
    # from), to]. For a reported position the last close values it however
    # old, the fallback (snapshot price) only before any close; otherwise a
    # close values the STALE_CLOSE_DAYS after it and no longer. A day's
    # price therefore depends only on the closes in its own look-back, never
    # on where the window started.
    #
    # Also records into flows the value that changes on a day with no ledger
    # trade behind it: a synthetic_dates quantity change (a custodian exit),
    # or a holding starting or stopping being valued with its quantity
    # unchanged (its price going stale, reappearing, or first existing).
    # The first day walked is the baseline and never carries a flow.
    sig do
      params(series: T::Hash[Date, Float], quantities: T::Hash[Date, BigDecimal],
             closes: T::Hash[Date, BigDecimal], from: Date, to: Date,
             fallback_price: T.nilable(BigDecimal), scale: Float, reported: T::Boolean,
             flows: T::Hash[Date, Float], synthetic_dates: T::Set[Date]).void
    end
    def self.add_valued_series!(series, quantities, closes, from, to, fallback_price: nil, scale: 1.0, reported: false,
                                flows: {}, synthetic_dates: Set.new)
      # quantities drives the date walk below, so an empty one has nothing to
      # value regardless of what prices exist.
      return if quantities.empty?

      change_dates = quantities.keys.sort
      close_dates  = closes.keys.sort
      qty          = BigDecimal("0")
      close_date   = T.let(nil, T.nilable(Date))
      qi = 0
      ci = 0

      # Seek to the window instead of walking every day since the first-ever
      # trade: fold in the quantity changes before it, then walk only
      # [start, to]. Closes before start are folded in by the walk itself.
      start = [ T.must(change_dates.first), from ].max
      while qi < change_dates.size && T.must(change_dates[qi]) < start
        qty = T.must(quantities[T.must(change_dates[qi])])
        qi += 1
      end

      # Nothing was held before a holding's first change, so a start inside
      # the window has a zero baseline; a start at the window's edge has none.
      previous = T.let(start > from ? 0.0 : nil, T.nilable(Float))
      (start..to).each do |date|
        changed = T.let(false, T::Boolean)
        while qi < change_dates.size && T.must(change_dates[qi]) <= date
          qty = T.must(quantities[T.must(change_dates[qi])])
          qi += 1
          changed = true
        end
        while ci < close_dates.size && T.must(close_dates[ci]) <= date
          close_date = close_dates[ci]
          ci += 1
        end

        # A position the custodian still reports is really there, so its last
        # known close (a bond priced on the last sync, a monthly NAV) beats
        # jumping to the current snapshot price; the snapshot only fills in
        # before any close exists. Only ledger-only holdings — nobody vouches
        # they still exist — stop being valued once their closes go stale.
        value_price = if reported
          close_date ? closes[close_date] : fallback_price
        elsif close_date && close_date >= date - STALE_CLOSE_DAYS
          closes[close_date]
        end
        # A non-positive net ledger means missing history (transfers-in,
        # unsynced buys) — reconciliation's problem to flag, never a
        # negative holding to chart.
        amount = qty.positive? && value_price ? (qty * value_price).to_f * scale : nil

        unless previous.nil?
          synthetic = changed ? synthetic_dates.include?(date) : previous.zero? != amount.nil?
          flows[date] = flows.fetch(date, 0.0) + (amount.to_f - previous) if synthetic
        end
        previous = amount.to_f

        series[date] = series[date].to_f + amount if amount
      end
    end
    private_class_method :add_valued_series!

    sig { params(account_ids: T.nilable(T::Array[String])).returns(T::Array[[ String, String ]]) }
    def self.ledger_pairs(account_ids)
      scope = InvestmentTransaction
        .joins(:transaction_type)
        .where(transaction_types: { category: Positions::Rebuild::POSITION_CATEGORIES })
        .where.not(account_id: nil).where.not(security_id: nil)
      scope = scope.where(account_id: account_ids) if account_ids
      scope.distinct.pluck(:account_id, :security_id)
    end
    private_class_method :ledger_pairs
  end
end
