require "rails_helper"

# Rule-by-rule behavior is covered through TaxScanJob's spec; this pins the
# service contract: events come back as [name, payload] and nothing is
# published.
RSpec.describe Tax::VigilanceScan do
  let(:household) { Current.household }
  let(:year)      { 2026 }

  it "returns events without publishing them" do
    report = {
      payments:      { due_dates: [ { date: "2026-06-15", jurisdiction: "federal", label: "Q2", paid_in_window: 0 } ],
                       safe_harbor: { federal: { status: "uncovered", required_annual: 1000, paid: 0 } } },
      contributions: { buckets: [] },
      flags:         { wash_sales: [] }
    }
    allow(Tax::YearReport).to receive(:build).and_return(report)

    expect(Workflows::Events).not_to receive(:publish)
    events = described_class.new(household: household, year: year, today: Date.new(2026, 6, 1)).events

    expect(events).to include(
      [ "tax.quarterly_due_approaching", { "jurisdiction" => "federal", "date" => "2026-06-15", "label" => "Q2" } ],
      [ "tax.safe_harbor_behind", { "jurisdiction" => "federal", "required_annual" => 1000, "paid" => 0 } ]
    )
  end
end
