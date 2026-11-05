require "rails_helper"

# Event selection lives here; EquityVestScanJob's spec covers publishing.
RSpec.describe Equity::VestScan do
  let(:company) { create(:equity_company) }
  let(:today)   { Date.new(2026, 6, 10) }

  before do
    create(:equity_fmv_entry, equity_company: company, price_per_share: 10, effective_date: today - 1.month)
  end

  def rsu(dates, **attrs)
    create(:equity_grant, :rsu, equity_company: company, quantity: dates.size * 10,
           vesting_interval: nil, vesting_occurrences: nil, cliff_installments: 0,
           grant_date: today - 1.year,
           custom_tranches: dates.map { |d| { "date" => d.iso8601, "quantity" => 10 } }, **attrs)
  end

  it "returns upcoming and same-day vests with their value, without publishing" do
    grant = rsu([ today + 14, today, today + 7 ])

    expect(Workflows::Events).not_to receive(:publish)
    expect(described_class.new(grant, today: today).events).to contain_exactly(
      [ "equity.vest_upcoming", { "tranche_date" => (today + 14).iso8601, "quantity" => 10.0, "value" => 100.0 } ],
      [ "equity.vest_occurred", { "tranche_date" => today.iso8601, "quantity" => 10.0, "value" => 100.0 } ]
    )
  end

  it "returns nothing on an ordinary day" do
    expect(described_class.new(rsu([ today + 7 ]), today: today).events).to eq([])
  end
end
