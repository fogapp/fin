require "rails_helper"

RSpec.describe NetWorthHistory, "equity" do
  # A grant that vested in full two months ago, so "vested today" and "vested
  # at the start of a 3m window" are easy to tell apart.
  def vested_grant(company, *traits, quantity: 1000, price: 10, granted: 2.months.ago.to_date, **attrs)
    create(:equity_fmv_entry, equity_company: company, price_per_share: price, effective_date: granted)
    create(:equity_grant, :fully_vested, *traits, equity_company: company, grant_date: granted,
                                         vesting_commencement_date: granted, quantity: quantity, **attrs)
  end

  it "counts vested RSU value as an asset in its own bucket" do
    company = create(:equity_company)
    vested_grant(company, :rsu, quantity: 1000, price: 10, strike_price: nil)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:equity]).to eq(10_000.0)
    expect(result[:stats][:assets]).to eq(10_000.0)
    expect(result[:stats][:net_worth]).to eq(10_000.0)
    expect(result[:series].last[:equity]).to eq(10_000.0)
  end

  it "values options at their intrinsic spread" do
    company = create(:equity_company)
    vested_grant(company, quantity: 1000, price: 10, strike_price: 4)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:equity]).to eq(6_000.0)
  end

  it "treats underwater options as worthless rather than negative" do
    company = create(:equity_company)
    vested_grant(company, quantity: 1000, price: 10, strike_price: 25)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:equity]).to eq(0.0)
    expect(result[:equity]).to be_empty
  end

  it "excludes unvested shares by default and steps value up on each vest" do
    company = create(:equity_company)
    create(:equity_fmv_entry, equity_company: company, price_per_share: 10, effective_date: 1.year.ago.to_date)
    create(:equity_grant, :rsu, equity_company: company, quantity: 400, strike_price: nil,
                                grant_date: 1.year.ago.to_date, vesting_commencement_date: 1.year.ago.to_date,
                                vesting_interval: "monthly", vesting_occurrences: 4, cliff_installments: 0)

    result = described_class.new(range: NetWorthHistory::RangeKey::OneYear).call

    # 4 monthly tranches of 100, all vested by 8 months ago.
    expect(result[:stats][:equity]).to eq(4_000.0)
    two_months_in = result[:series].find { |r| r[:date] >= (1.year.ago.to_date + 2.months).iso8601 }
    expect(two_months_in[:equity]).to eq(2_000.0)
  end

  it "counts unvested shares when the household opts in" do
    Current.household.update!(include_unvested_equity: true)
    company = create(:equity_company)
    create(:equity_fmv_entry, equity_company: company, price_per_share: 10, effective_date: 1.month.ago.to_date)
    create(:equity_grant, :rsu, equity_company: company, quantity: 400, strike_price: nil,
                                grant_date: 1.month.ago.to_date, vesting_commencement_date: 1.month.ago.to_date,
                                vesting_interval: "monthly", vesting_occurrences: 4, cliff_installments: 0)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:equity]).to eq(4_000.0)
    expect(result[:equity].first[:vested_value]).to eq(1_000.0)
    expect(result[:equity].first[:unvested_value]).to eq(3_000.0)
  end

  it "drops exercised shares out of the bucket so brokerage holdings aren't double-counted" do
    company = create(:equity_company)
    grant = vested_grant(company, quantity: 1000, price: 10, strike_price: 4)
    create(:equity_grant_event, equity_grant: grant, kind: "exercise",
                                quantity: 400, occurred_on: 1.month.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:equity]).to eq(3_600.0)
    before_exercise = result[:series].find { |r| r[:date] == (1.month.ago.to_date - 5).iso8601 }
    expect(before_exercise[:equity]).to eq(6_000.0)
  end

  it "does not subtract a sale of shares an exercise already removed" do
    company = create(:equity_company)
    grant = vested_grant(company, quantity: 1000, price: 10, strike_price: 4)
    create(:equity_grant_event, equity_grant: grant, kind: "exercise", quantity: 400, occurred_on: 20.days.ago.to_date)
    create(:equity_grant_event, equity_grant: grant, kind: "sale", quantity: 400, occurred_on: 10.days.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:equity]).to eq(3_600.0)
  end

  it "reprices history as the FMV history moves" do
    company = create(:equity_company)
    create(:equity_fmv_entry, equity_company: company, price_per_share: 5,  effective_date: 3.months.ago.to_date)
    create(:equity_fmv_entry, equity_company: company, price_per_share: 20, effective_date: 1.month.ago.to_date)
    create(:equity_grant, :rsu, :fully_vested, equity_company: company, quantity: 100, strike_price: nil,
                                               grant_date: 3.months.ago.to_date,
                                               vesting_commencement_date: 3.months.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    old = result[:series].find { |r| r[:date] == (2.months.ago.to_date).iso8601 }
    expect(old[:equity]).to eq(500.0)
    expect(result[:stats][:equity]).to eq(2_000.0)
  end

  it "carries the oldest known FMV backwards rather than valuing history at zero" do
    company = create(:equity_company)
    create(:equity_fmv_entry, equity_company: company, price_per_share: 12, effective_date: Date.current)
    create(:equity_grant, :rsu, :fully_vested, equity_company: company, quantity: 100, strike_price: nil,
                                               grant_date: 6.months.ago.to_date,
                                               vesting_commencement_date: 6.months.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:series].first[:equity]).to eq(1_200.0)
  end

  it "prices a public company off its linked security's daily closes" do
    security = create(:security)
    company  = create(:equity_company, public_company: true, security: security)
    create(:candle, security: security, date: 2.months.ago.to_date, close: 30, adjusted_close: 30)
    create(:candle, security: security, date: Date.current,         close: 50, adjusted_close: 50)
    create(:equity_grant, :rsu, :fully_vested, equity_company: company, quantity: 100, strike_price: nil,
                                               grant_date: 2.months.ago.to_date,
                                               vesting_commencement_date: 2.months.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    old = result[:series].find { |r| r[:date] == 1.month.ago.to_date.iso8601 }
    expect(old[:equity]).to eq(3_000.0)
    expect(result[:stats][:equity]).to eq(5_000.0)
  end

  it "contributes nothing when the company has no price at all" do
    company = create(:equity_company)
    create(:equity_grant, :rsu, :fully_vested, equity_company: company, quantity: 100, strike_price: nil,
                                               grant_date: 2.months.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:equity]).to eq(0.0)
  end

  it "reports a per-company breakdown row" do
    company = create(:equity_company, name: "Acme")
    vested_grant(company, :rsu, quantity: 1000, price: 10, strike_price: nil)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call
    row = result[:equity].first

    expect(row[:name]).to eq("Acme")
    expect(row[:value]).to eq(10_000.0)
    expect(row[:grant_count]).to eq(1)
    expect(row[:include_unvested]).to be(false)
  end

  it "widens the all range back to the earliest grant" do
    company = create(:equity_company)
    vested_grant(company, :rsu, quantity: 100, price: 10, strike_price: nil, granted: 3.years.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::All).call

    expect(Date.iso8601(result[:series].first[:date])).to be <= 3.years.ago.to_date
  end
end
