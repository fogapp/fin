# typed: strict

class SecurityOverviewSyncer
  extend T::Sig

  sig { params(security: Security).void }
  def initialize(security)
    @security = T.let(security, Security)
    @client   = T.let(AlphaVantage::Client.new, T.untyped)
  end

  sig { returns(T.nilable(SecurityOverview)) }
  def call
    raw = @client.company_overview(@security.ticker)
    return unless raw

    overview = SecurityOverview.find_or_initialize_by(security: @security)
    overview.update!(
      sector:               raw["Sector"].presence,
      industry:             raw["Industry"].presence,
      exchange:             raw["Exchange"].presence,
      country:              raw["Country"].presence,
      currency:             raw["Currency"].presence,
      description:          raw["Description"].presence,
      market_cap:           parse_int(raw["MarketCapitalization"]),
      shares_outstanding:   parse_int(raw["SharesOutstanding"]),
      revenue_ttm:          parse_int(raw["RevenueTTM"]),
      pe_ratio:             parse_decimal(raw["PERatio"]),
      forward_pe:           parse_decimal(raw["ForwardPE"]),
      eps:                  parse_decimal(raw["EPS"]),
      beta:                 parse_decimal(raw["Beta"]),
      dividend_yield:       parse_decimal(raw["DividendYield"]),
      dividend_per_share:   parse_decimal(raw["DividendPerShare"]),
      week_52_high:         parse_decimal(raw["52WeekHigh"]),
      week_52_low:          parse_decimal(raw["52WeekLow"]),
      analyst_target_price: parse_decimal(raw["AnalystTargetPrice"]),
      profit_margin:        parse_decimal(raw["ProfitMargin"]),
      return_on_equity:     parse_decimal(raw["ReturnOnEquityTTM"]),
      ex_dividend_date:     parse_date(raw["ExDividendDate"]),
      fetched_at:           Time.current
    )
    overview
  end

  private

  sig { params(val: T.untyped).returns(T.nilable(BigDecimal)) }
  def parse_decimal(val)
    return nil if val.blank? || val == "None" || val == "-"
    BigDecimal(val.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  sig { params(val: T.untyped).returns(T.nilable(Integer)) }
  def parse_int(val)
    return nil if val.blank? || val == "None" || val == "-"
    v = val.to_i
    v.zero? ? nil : v
  end

  sig { params(val: String).returns(T.nilable(Date)) }
  def parse_date(val)
    return nil if val.blank? || val == "None" || val == "0000-00-00"
    Date.parse(val)
  rescue Date::Error, TypeError
    nil
  end
end
