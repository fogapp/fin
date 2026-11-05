require "rails_helper"

RSpec.describe Transfers::PaymentBackfill do
  it "bumps the household data version once so cached endpoints rotate" do
    # The sweep's normalize step writes via update_all, which skips the
    # after_commit bump.
    expect(Households::DataVersion).to receive(:bump!).with(Current.household.id).once
    described_class.new.call
  end
end
