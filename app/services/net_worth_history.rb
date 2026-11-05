# typed: strict

# Reconstructs household net worth over time by stitching together the three
# places balance history lives:
#
#   1. AccountBalanceSnapshot rows for cash / credit / crypto accounts —
#      last snapshot per day, carried forward between snapshots, with the
#      account's live balance providing today's point
#   2. Valuation::PortfolioSeries.call_by_account for accounts that have
#      position snapshots — ledger quantities anchored to the latest
#      snapshot, valued at adjusted daily closes
#   3. Loan#balance_breakpoints for active loans — payment replay from
#      origination (or the balance anchor)
#   4. RealEstateProperty#value_breakpoints and Equity::ValueHistory, which
#      already emit carry-forward [date, value] points of their own
#
# Accounts are bucketed into cash / investments / crypto / credit groups by
# account_type; any account with position snapshots counts as investments
# regardless of type, and is valued from positions rather than balance
# snapshots so the two sources never double-count.
#
# call returns a chart-ready payload: a sampled series over the requested
# range (credit/loans emitted as negatives so they stack below zero), current
# stats with 1m/3m/ytd/1y changes, net change per month for the trailing
# year, and a per-account / per-loan breakdown over the range.
#
# The window is either a named RangeKey (always ending today) or an explicit
# from/to, which may end in the past ("2025", "last month"). Stats and
# monthly deltas stay anchored to today either way; the series and the
# breakdown's start/end values follow the window.
class NetWorthHistory
  extend T::Sig

  # Named chart window. RangeKey (not Range) — a nested `Range` constant
  # would shadow ::Range inside this class; "3m"/"1y" aren't valid constant
  # names, hence ThreeMonths/OneYear.
  class RangeKey < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      ThreeMonths = new("3m")
      Ytd = new("ytd")
      OneYear = new("1y")
      All = new("all")
    end
  end

  DEFAULT_RANGE = RangeKey::OneYear

  # Ranges longer than this many days are sampled weekly instead of daily.
  DAILY_SAMPLING_LIMIT = 400

  sig { params(range: T.nilable(RangeKey), from: T.nilable(Date), to: T.nilable(Date)).void }
  def initialize(range: nil, from: nil, to: nil)
    @today = T.let(Date.current, Date)
    @range = T.let(range || DEFAULT_RANGE, RangeKey)
    # An explicit window never runs past today (there's nothing to value),
    # and a from after the clamped end collapses to a single day.
    @range_end = T.let([ to || @today, @today ].min, Date)
    @from      = T.let(from && [ from, @range_end ].min, T.nilable(Date))
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def call
    # External accounts carry no balance data (transfer counterparties only)
    # and must not appear in net-worth math or the account breakdown.
    accounts         = ::Account.where(hidden: false).where.not(kind: "external").includes(:broker).to_a
    position_ids     = ::PositionSnapshot.where(account_id: accounts.map(&:id)).distinct.pluck(:account_id).to_set
    all_loans        = ::Loan.where(status: ::Loan::Status::Active).to_a
    loan_account_ids = all_loans.filter_map(&:account_id).to_set
    group_of         = accounts.to_h { |a| [ a.id, classify(a, position_ids, loan_account_ids) ] }

    # Loans whose linked account is in scope are valued from that account's
    # balance history (synced, so more authoritative than payment replay);
    # only unlinked loans get the amortization-replay treatment.
    account_ids = accounts.map(&:id).to_set
    loans       = all_loans.reject { |l| (account_id = l.account_id) && account_ids.include?(account_id) }

    # Real estate is valued from its own valuation history, which already
    # carries forward the same way balance snapshots do.
    properties = ::RealEstateProperty.includes(:valuations, loans: :cash_transactions).to_a

    range_start  = resolve_range_start(accounts, all_loans, properties)
    compute_from = [ range_start, @today - 1.year, @today.beginning_of_year ].min

    # Equity comp is priced from vest dates × FMV/quote history. Vested-only
    # by default; the household can opt into counting unvested shares too.
    equity = ::Equity::ValueHistory.new(
      from:             compute_from,
      to:               @today,
      include_unvested: ::Current.household&.include_unvested_equity || false
    )

    balance_accounts = accounts.reject { |a| position_ids.include?(a.id) }
    points_by_account = balance_breakpoints_by_account(balance_accounts, compute_from)
      .merge(portfolio_breakpoints_by_account(position_ids, compute_from))
    points_by_loan = loans.to_h { |l| [ l.id, l.balance_breakpoints.map { |d, b| [ d, b.to_f ] } ] }
    points_by_property = properties.to_h { |p| [ p.id, p.value_breakpoints ] }
    points_by_company  = equity.breakpoints_by_company

    sample_dates = build_sample_dates(range_start, @range_end)
    anchors      = { "1m" => @today << 1, "3m" => @today << 3, "ytd" => @today.beginning_of_year, "1y" => @today - 1.year }
    month_ends   = (0..12).map { |k| [ (@today << k).end_of_month, @today ].min }.sort
    all_dates    = (sample_dates + anchors.values + month_ends + [ @today ]).uniq.sort

    account_values  = points_by_account.transform_values { |pts| values_at(pts, all_dates) }
    loan_values     = points_by_loan.transform_values { |pts| values_at(pts, all_dates) }
    property_values = points_by_property.transform_values { |pts| values_at(pts, all_dates) }
    company_values  = points_by_company.transform_values { |pts| values_at(pts, all_dates) }

    valuations = all_dates.to_h { |d| [ d, valuation(d, group_of, account_values, loan_values, property_values, company_values) ] }
    now        = T.must(valuations[@today])

    {
      range:          @range,
      from:           range_start,
      to:             @range_end,
      series:         sample_dates.map { |d| series_row(d, T.must(valuations[d])) },
      stats:          stats(now, anchors, valuations),
      monthly_deltas: monthly_deltas(month_ends, valuations),
      accounts:       account_breakdown(accounts, group_of, account_values, range_start),
      loans:          loan_breakdown(loans, loan_values, range_start),
      properties:     property_breakdown(properties, property_values, range_start),
      equity:         equity_breakdown(equity.companies, company_values, range_start)
    }
  end

  private

  sig { params(account: T.untyped, position_ids: T.untyped, loan_account_ids: T.untyped).returns(Symbol) }
  def classify(account, position_ids, loan_account_ids)
    return :investments if position_ids.include?(account.id)
    return :loans       if loan_account_ids.include?(account.id)

    type = account.account_type.to_s.downcase
    case type
    when "credit card"                            then :credit
    when "crypto"                                 then :crypto
    when "brokerage", "retirement", "ira", "401k" then :investments
    when "loan", "mortgage", "heloc"              then :loans
    else
      # Plaid maps loan-type accounts to "Other", so an untyped account named
      # like a loan is far more likely a liability than cash.
      if [ "", "other" ].include?(type) && account.name.to_s.match?(/\b(mortgage|loan|heloc)\b/i)
        :loans
      else
        :cash
      end
    end
  end

  sig { params(accounts: T.untyped, loans: T.untyped, properties: T.untyped).returns(Date) }
  def resolve_range_start(accounts, loans, properties)
    return @from if @from

    case @range
    when RangeKey::ThreeMonths then @today << 3
    when RangeKey::Ytd then @today.beginning_of_year
    when RangeKey::OneYear then @today - 1.year
    else # RangeKey::All — earliest date any source has data for
      candidates = []
      if accounts.any?
        first_snap = ::AccountBalanceSnapshot.where(account_id: accounts.map(&:id)).minimum(:recorded_at)
        candidates << first_snap.to_date if first_snap
      end
      candidates << ::PositionSnapshot.minimum(:as_of_date)
      candidates << ::InvestmentTransaction.minimum(:trade_date)
      candidates.concat(loans.map(&:start_date))
      # A 2018 purchase (or a seeded tax-assessment year) should widen the
      # "all" window the same way an old account snapshot does.
      candidates.concat(properties.filter_map { |p| p.value_breakpoints.first&.first })
      # Cheap probe (min grant_date) rather than building the equity series,
      # which needs the window this method is resolving.
      candidates << ::Equity::ValueHistory.earliest_date
      [ candidates.compact.min || @today - 1.year, @today - 1.month ].min
    end
  end

  sig { params(range_start: Date, range_end: Date).returns(T::Array[Date]) }
  def build_sample_dates(range_start, range_end)
    step  = (range_end - range_start).to_i > DAILY_SAMPLING_LIMIT ? 7 : 1
    dates = []
    d = range_end
    while d > range_start
      dates << d
      d -= step
    end
    dates << range_start
    dates.reverse
  end

  # One breakpoint per account per day: the day's last snapshot, preceded by
  # a warmup point (latest snapshot before the window) so carry-forward works
  # from the first sample date, and capped with the account's live balance as
  # today's point.
  sig { params(accounts: T.untyped, compute_from: Date).returns(T::Hash[String, T::Array[T.untyped]]) }
  def balance_breakpoints_by_account(accounts, compute_from)
    ids = accounts.map(&:id)
    points = Hash.new { |h, k| h[k] = [] }
    return {} if ids.empty?

    # Local-day bucketing (see AccountBalanceSnapshot.local_date) so day
    # labels match Time.zone day boundaries, not UTC's.
    day = ::AccountBalanceSnapshot.local_date

    warmup = ::AccountBalanceSnapshot
      .where(account_id: ids)
      .where("recorded_at < ?", compute_from)
      .select("DISTINCT ON (account_id) account_id, balance, balance_usd")
      .select(day.as("snap_date"))
      .order(:account_id, recorded_at: :desc)

    window = ::AccountBalanceSnapshot
      .where(account_id: ids)
      .where(recorded_at: compute_from.beginning_of_day..)
      .select("DISTINCT ON (account_id, #{day.to_sql}) account_id, balance, balance_usd")
      .select(day.as("snap_date"))
      .order(:account_id, day, recorded_at: :desc)

    (warmup.to_a + window.to_a).each do |row|
      attrs = row.attributes
      points[attrs["account_id"]] << [ attrs["snap_date"].to_date, (attrs["balance_usd"] || attrs["balance"]).to_f ]
    end

    accounts.each do |account|
      live = account.balance_usd || account.balance
      next if live.nil?
      pts = points[account.id]
      pts.reject! { |date, _| date == @today }
      pts << [ @today, live.to_f ]
    end

    points.each_value { |pts| pts.sort_by!(&:first) }
    points
  end

  sig { params(position_ids: T.untyped, compute_from: Date).returns(T::Hash[String, T::Array[T.untyped]]) }
  def portfolio_breakpoints_by_account(position_ids, compute_from)
    return {} if position_ids.empty?

    Valuation::PortfolioSeries.call_by_account(from: compute_from, to: @today, account_ids: position_ids.to_a)
                              .transform_values { |series| series.sort.map { |date, value| [ date, value ] } }
  end

  # Carry-forward lookup: for each date, the value of the latest breakpoint
  # on or before it (nil before the first breakpoint — the account or loan
  # didn't exist yet). Both inputs must be sorted ascending.
  sig { params(points: T::Array[T.untyped], dates: T::Array[Date]).returns(T::Hash[Date, T.nilable(Float)]) }
  def values_at(points, dates)
    out = {}
    idx = 0
    current = T.let(nil, T.nilable(Float))
    dates.each do |date|
      while idx < points.size && points[idx][0] <= date
        current = points[idx][1]
        idx += 1
      end
      out[date] = current
    end
    out
  end

  sig do
    params(date: Date, group_of: T.untyped, account_values: T.untyped, loan_values: T.untyped,
           property_values: T.untyped, company_values: T.untyped).returns(T::Hash[Symbol, Float])
  end
  def valuation(date, group_of, account_values, loan_values, property_values, company_values)
    sums = Hash.new(0.0)
    account_values.each do |account_id, values|
      value = values[date]
      sums[group_of[account_id]] += value if value
    end

    # Gross property value. The mortgage financing it stays in :loans, so
    # equity falls out of the two buckets without double-counting.
    real_estate = property_values.sum { |_, values| values[date] || 0.0 }
    equity      = company_values.sum { |_, values| values[date] || 0.0 }
    loans       = sums[:loans] + loan_values.sum { |_, values| values[date] || 0.0 }
    assets      = sums[:cash] + sums[:investments] + sums[:crypto] + real_estate + equity
    liabilities = sums[:credit] + loans

    {
      cash:        sums[:cash],
      investments: sums[:investments],
      crypto:      sums[:crypto],
      real_estate: real_estate,
      equity:      equity,
      credit:      sums[:credit],
      loans:       loans,
      assets:      assets,
      liabilities: liabilities,
      net:         assets - liabilities
    }
  end

  sig { params(date: Date, v: T::Hash[Symbol, Float]).returns(T::Hash[Symbol, T.untyped]) }
  def series_row(date, v)
    {
      date:        date.iso8601,
      cash:        round(v[:cash]),
      investments: round(v[:investments]),
      crypto:      round(v[:crypto]),
      real_estate: round(v[:real_estate]),
      equity:      round(v[:equity]),
      credit:      round(-T.must(v[:credit])),
      loans:       round(-T.must(v[:loans])),
      assets:      round(v[:assets]),
      liabilities: round(v[:liabilities]),
      net:         round(v[:net])
    }
  end

  sig { params(now: T::Hash[Symbol, Float], anchors: T::Hash[String, Date], valuations: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def stats(now, anchors, valuations)
    changes = anchors.to_h do |label, date|
      past   = valuations[date][:net]
      amount = T.must(now[:net]) - past
      [ label, { amount: round(amount), pct: pct_change(now[:net], past) } ]
    end

    {
      net_worth:   round(now[:net]),
      assets:      round(now[:assets]),
      liabilities: round(now[:liabilities]),
      cash:        round(now[:cash]),
      investments: round(now[:investments]),
      crypto:      round(now[:crypto]),
      real_estate: round(now[:real_estate]),
      equity:      round(now[:equity]),
      credit:      round(now[:credit]),
      loans:       round(now[:loans]),
      changes:     changes
    }
  end

  sig { params(month_ends: T::Array[Date], valuations: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def monthly_deltas(month_ends, valuations)
    month_ends.each_cons(2).map do |pair|
      prev_end, month_end = T.must(pair[0]), T.must(pair[1])
      {
        month:  month_end.strftime("%Y-%m"),
        change: round(valuations[month_end][:net] - valuations[prev_end][:net])
      }
    end
  end

  sig { params(accounts: T.untyped, group_of: T.untyped, account_values: T.untyped, range_start: Date).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def account_breakdown(accounts, group_of, account_values, range_start)
    accounts.filter_map do |account|
      values      = account_values[account.id] || {}
      value       = values[@range_end] || 0.0
      # nil (not 0) when the account had no data at range start — a balance
      # history that only begins mid-window must not read as growth from zero.
      start_value = values[range_start]
      next if value.zero? && start_value.to_f.zero?

      {
        id:           account.id,
        name:         account.name,
        broker:       account.broker&.name,
        account_type: account.account_type,
        group:        group_of[account.id].to_s,
        value:        round(value),
        start_value:  start_value.nil? ? nil : round(start_value),
        change:       round(value - start_value.to_f),
        change_pct:   pct_change(value, start_value)
      }
    end.sort_by { |row| -row[:value].abs }
  end

  sig { params(loans: T.untyped, loan_values: T.untyped, range_start: Date).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def loan_breakdown(loans, loan_values, range_start)
    loans.filter_map do |loan|
      values      = loan_values[loan.id] || {}
      value       = values[@range_end] || 0.0
      start_value = values[range_start]
      next if value.zero? && start_value.to_f.zero?

      {
        id:          loan.id,
        name:        loan.name,
        loan_type:   loan.loan_type,
        lender:      loan.lender,
        value:       round(value),
        start_value: start_value.nil? ? nil : round(start_value),
        change:      round(value - start_value.to_f),
        change_pct:  pct_change(value, start_value)
      }
    end.sort_by { |row| -row[:value].abs }
  end

  # Properties carry their mortgage balance and equity alongside the gross
  # value, so the breakdown can show all three without a second round trip.
  sig { params(properties: T.untyped, property_values: T.untyped, range_start: Date).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def property_breakdown(properties, property_values, range_start)
    properties.filter_map do |property|
      values      = property_values[property.id] || {}
      value       = values[@range_end] || 0.0
      start_value = values[range_start]
      next if value.zero? && start_value.to_f.zero?

      mortgage = property.mortgage_balance
      {
        id:               property.id,
        name:             property.name,
        address:          property.query_address,
        status:           property.status,
        value:            round(value),
        start_value:      start_value.nil? ? nil : round(start_value),
        change:           round(value - start_value.to_f),
        change_pct:       pct_change(value, start_value),
        mortgage_balance: mortgage.nil? ? nil : round(mortgage),
        equity:           mortgage.nil? ? round(value) : round(value - mortgage.to_f)
      }
    end.sort_by { |row| -row[:value].abs }
  end

  # One row per company holding equity comp, carrying the vested/unvested
  # split alongside the value actually counted so the UI can show what was
  # left out when the household counts vested shares only.
  sig { params(companies: T.untyped, company_values: T.untyped, range_start: Date).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def equity_breakdown(companies, company_values, range_start)
    include_unvested = ::Current.household&.include_unvested_equity || false

    companies.filter_map do |company|
      values      = company_values[company.id] || {}
      value       = values[@range_end] || 0.0
      start_value = values[range_start]
      next if value.zero? && start_value.to_f.zero?

      price = ::Equity::Valuation.current_share_price(company)
      vested, unvested = company.grants.reduce([ 0.0, 0.0 ]) do |(v, u), grant|
        calculator = grant.calculator
        [
          v + (::Equity::Valuation.grant_value(grant, calculator.vested_quantity, price) || 0).to_f,
          u + (::Equity::Valuation.grant_value(grant, calculator.unvested_quantity, price) || 0).to_f
        ]
      end

      {
        id:               company.id,
        name:             company.name,
        ticker:           company.security&.ticker,
        public_company:   company.public_company?,
        grant_count:      company.grants.size,
        value:            round(value),
        start_value:      start_value.nil? ? nil : round(start_value),
        change:           round(value - start_value.to_f),
        change_pct:       pct_change(value, start_value),
        vested_value:     round(vested),
        unvested_value:   round(unvested),
        include_unvested: include_unvested
      }
    end.sort_by { |row| -row[:value].abs }
  end

  sig { params(value: T.untyped).returns(Float) }
  def round(value)
    value.to_f.round(2) + 0 # + 0 normalizes -0.0
  end

  sig { params(current: T.untyped, previous: T.untyped).returns(T.nilable(Float)) }
  def pct_change(current, previous)
    return nil if previous.nil? || previous.to_f.zero?
    ((current.to_f - previous.to_f) / previous.to_f.abs * 100).round(2)
  end
end
