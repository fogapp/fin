require "rails_helper"

RSpec.describe RentcastConfiguration do
  describe "#consume_quota!" do
    it "counts each request against the monthly allowance" do
      config = create(:rentcast_configuration, monthly_request_limit: 50)

      3.times { config.consume_quota! }

      expect(config.reload.requests_used).to eq(3)
      expect(config.remaining_quota).to eq(47)
    end

    it "raises rather than exceeding the limit" do
      config = create(:rentcast_configuration, monthly_request_limit: 2, requests_used: 2,
                                               quota_period_start: Date.current.beginning_of_month)

      expect { config.consume_quota! }.to raise_error(described_class::QuotaExceeded, /limit reached/)
      expect(config.reload.requests_used).to eq(2)
    end

    it "persists immediately, so a crash mid-refresh doesn't hand the request back" do
      config = create(:rentcast_configuration)
      config.consume_quota!

      expect(described_class.unscoped.find(config.id).requests_used).to eq(1)
    end

    it "zeroes the counter when the calendar month rolls over" do
      config = create(:rentcast_configuration, requests_used: 48,
                                               quota_period_start: Date.current.beginning_of_month - 1.month)

      expect(config.remaining_quota).to eq(50)
      expect(config.reload.requests_used).to eq(0)
    end
  end
end
