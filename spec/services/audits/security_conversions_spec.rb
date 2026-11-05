require "rails_helper"

RSpec.describe Audits::SecurityConversions do
  let(:from) { create(:security, ticker: "SMNEY", name: "Siemens Energy Ag-Unsp") }
  let(:to)   { create(:security, ticker: "SMERY", name: "Siemens Energy AG - ADR - Sponsored") }

  def suggestion!(**attrs)
    SecurityConversion.create!(
      from_security: from, to_security: to, effective_date: Date.new(2026, 1, 30), ratio: 5,
      evidence: { "account_name" => "Global", "from" => { "last_close_date" => "2026-01-29", "ledger_quantity" => 582.0 },
                  "to" => { "unexplained_quantity" => 2910.0 }, "value_gap_pct" => 3.75 },
      **attrs
    )
  end

  before { allow(Instruments::ConversionDetector).to receive(:new).and_return(instance_double(Instruments::ConversionDetector, call: [])) }

  it "raises one readable issue per suggested conversion" do
    conversion = suggestion!

    described_class.new.call

    issue = Issue.active.find_by!(key: "security_conversion:#{conversion.id}")
    expect(issue.title).to eq("Possible conversion: SMNEY → SMERY in Global (Jan 30, 2026)")
    expect(issue.body).to include("582.0 shares", "2910.0", "Suggested ratio: 5.0", "3.75%")
  end

  it "resolves the issue once the suggestion is confirmed or dismissed" do
    confirmed = suggestion!
    described_class.new.call
    confirmed.confirm!

    expect(Issue.active.where(key: confirmed.issue_key)).to be_empty
    expect(confirmed.reload.confirmed_at).to be_present
  end

  it "sweeps issues whose conversion is gone" do
    conversion = suggestion!
    described_class.new.call
    SecurityConversion.where(id: conversion.id).delete_all # bypasses callbacks

    described_class.new.call

    expect(Issue.active.where(key: conversion.issue_key)).to be_empty
  end

  it "recomputes the portfolio_value history on confirm" do
    conversion = suggestion!

    expect { conversion.confirm! }
      .to have_enqueued_job(Metrics::BackfillJob).with(conversion.household_id, "portfolio_value")
  end

  it "is part of the system audit" do
    expect(SystemAuditJob::AUDITS).to include(described_class)
  end
end
