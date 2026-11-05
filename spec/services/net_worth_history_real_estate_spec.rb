require "rails_helper"

RSpec.describe NetWorthHistory, "real estate" do
  def property_worth(amount, as_of: Date.current, **attrs)
    property = create(:real_estate_property, **attrs)
    property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: as_of, amount: amount)
    property
  end

  it "counts property value as an asset in its own bucket" do
    property_worth(900_000)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:real_estate]).to eq(900_000.0)
    expect(result[:stats][:assets]).to eq(900_000.0)
    expect(result[:stats][:net_worth]).to eq(900_000.0)
    expect(result[:series].last[:real_estate]).to eq(900_000.0)
  end

  it "keeps a linked mortgage as a liability without double-counting" do
    property = property_worth(1_000_000)
    create(:loan, real_estate_property: property, original_principal: 400_000,
                  interest_rate: 6.0, term_months: 360, start_date: Date.current, status: "active")

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:real_estate]).to eq(1_000_000.0)
    expect(result[:stats][:loans]).to eq(400_000.0)
    expect(result[:stats][:net_worth]).to eq(600_000.0)
  end

  it "carries the last valuation forward between points" do
    property_worth(800_000, as_of: 30.days.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call
    mid = result[:series].find { |row| row[:date] == 10.days.ago.to_date.iso8601 }

    expect(mid[:real_estate]).to eq(800_000.0)
  end

  it "contributes nothing before the first valuation" do
    property_worth(800_000, as_of: 10.days.ago.to_date)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call
    early = result[:series].find { |row| row[:date] == 30.days.ago.to_date.iso8601 }

    expect(early[:real_estate]).to eq(0.0)
  end

  it "excludes tax assessments from the value" do
    property = property_worth(900_000, as_of: 5.days.ago.to_date)
    property.record_valuation!(source: RealEstateValuation::Source::TaxAssessment,
                               as_of: Date.current, amount: 640_000)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:stats][:real_estate]).to eq(900_000.0)
  end

  it "drops a sold property out of the total after the sale" do
    property = property_worth(900_000, as_of: 30.days.ago.to_date)
    property.update!(status: "sold", sold_date: 10.days.ago.to_date, sold_price: 925_000)

    result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

    expect(result[:series].find { |r| r[:date] == 20.days.ago.to_date.iso8601 }[:real_estate]).to eq(900_000.0)
    expect(result[:stats][:real_estate]).to eq(0.0)
  end

  describe "the properties breakdown" do
    it "reports value, mortgage, and equity per property" do
      property = property_worth(1_000_000, name: "Primary residence")
      create(:loan, real_estate_property: property, original_principal: 400_000,
                    interest_rate: 6.0, term_months: 360, start_date: Date.current, status: "active")

      row = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call[:properties].first

      expect(row[:name]).to eq("Primary residence")
      expect(row[:value]).to eq(1_000_000.0)
      expect(row[:mortgage_balance]).to eq(400_000.0)
      expect(row[:equity]).to eq(600_000.0)
    end

    it "leaves the mortgage nil and equity at full value with no loan linked" do
      property_worth(500_000)

      row = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call[:properties].first

      expect(row[:mortgage_balance]).to be_nil
      expect(row[:equity]).to eq(500_000.0)
    end
  end

  it "widens the all-time window back to the earliest valuation" do
    property_worth(500_000, as_of: Date.new(2019, 6, 1))

    result = described_class.new(range: NetWorthHistory::RangeKey::All).call

    expect(Date.iso8601(result[:series].first[:date])).to be <= Date.new(2019, 6, 1)
  end
end
