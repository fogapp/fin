require "rails_helper"

# Exercises the ApplicationRecord.typed_enum macro through Notification,
# the smallest model wired to it.
RSpec.describe "ApplicationRecord.typed_enum" do
  let(:household) { create(:household) }

  it "preserves the schema default as an enum instance" do
    expect(Notification.new.severity).to eq(Severity::Info)
    expect(Issue.new.severity).to eq(Severity::Warning)
  end

  it "casts assigned strings and symbols to enum instances" do
    n = Notification.new(severity: "critical")
    expect(n.severity).to eq(Severity::Critical)
    n.severity = :warning
    expect(n.severity).to eq(Severity::Warning)
  end

  it "accepts enum instances and persists the serialized string" do
    n = Notification.create!(household: household, title: "t", severity: Severity::Critical)
    expect(n.reload.severity).to eq(Severity::Critical)
    expect(n.severity_before_type_cast).to eq("critical")
  end

  it "rejects values outside the enum with an inclusion error" do
    n = Notification.new(household: household, title: "t", severity: "bogus")
    expect(n).not_to be_valid
    expect(n.errors[:severity]).to include("is not included in the list")
  end

  it "serializes enum instances in where clauses" do
    sql = ActivityEntry.where(severity: Severity::Error).to_sql
    expect(sql).to include("'error'")
  end

  it "JSON-encodes as the serialized string" do
    expect(ActiveSupport::JSON.encode(severity: Severity::Error)).to eq('{"severity":"error"}')
    expect(Severity::Error.to_s).to eq("error")
  end

  it "orders severities for thresholding" do
    expect(Severity::Critical.rank).to be > Severity::Error.rank
    expect(Severity::Critical.at_least?(Severity::Error)).to be(true)
    expect(Severity::Info.at_least?(Severity::Warning)).to be(false)
  end
end
