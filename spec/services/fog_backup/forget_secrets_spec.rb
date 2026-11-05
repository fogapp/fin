# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FogBackup::ForgetSecrets do
  it "clears every encrypted value and marks linked institutions for linking again, saying what it cleared" do
    item = create(:plaid_item, access_token: "access-sandbox-secret", institution_name: "First Bank")

    forgotten = described_class.run!

    item = PlaidItem.unscoped.find(item.id)
    expect(item.access_token).to eq(described_class::FORGOTTEN)
    expect(item).to be_error
    expect(item.error_message).to include("Link this institution again")
    expect(item.institution_name).to eq("First Bank")
    expect(forgotten).to include("PlaidItem" => [ "access_token" ], "PlaidConfiguration" => [ "client_id", "secret" ])
  end

  # Every encrypted attribute is either nullable or has a rule — a required
  # one added without a rule fails here, not in a restore.
  it "has a rule for every required encrypted attribute" do
    expect { described_class.run! }.not_to raise_error
  end
end
