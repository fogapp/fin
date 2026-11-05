require "rails_helper"

RSpec.describe RealEstate::SyncTickJob do
  let!(:config) { create(:rentcast_configuration, api_key: "test-key", monthly_request_limit: 50) }

  def quota_issue_key = "rentcast_quota_#{Current.household.id}"

  it "enqueues one refresh per syncable property" do
    a = create(:real_estate_property, facts_synced_at: 1.day.ago)
    b = create(:real_estate_property, facts_synced_at: 1.day.ago)

    expect { described_class.perform_now }
      .to have_enqueued_job(RealEstate::RefreshJob).twice

    expect([ a, b ].map(&:id)).to all(be_present)
  end

  it "skips properties that are manual-only or sold" do
    create(:real_estate_property, sync_enabled: false)
    create(:real_estate_property, status: "sold", sold_date: Date.current, sold_price: 1)

    expect { described_class.perform_now }.not_to have_enqueued_job(RealEstate::RefreshJob)
  end

  it "does nothing for a household without RentCast configured" do
    config.destroy!
    create(:real_estate_property)

    expect { described_class.perform_now }.not_to have_enqueued_job(RealEstate::RefreshJob)
  end

  describe "budget guard" do
    it "syncs nothing and raises an issue when the allowance can't cover the run" do
      create(:real_estate_property, facts_synced_at: 1.day.ago)
      create(:real_estate_property, facts_synced_at: 1.day.ago)
      config.update!(requests_used: 49, quota_period_start: Date.current.beginning_of_month)

      expect { described_class.perform_now }.not_to have_enqueued_job(RealEstate::RefreshJob)
      expect(Issue.active.where(key: quota_issue_key)).to be_present
    end

    it "counts a property whose facts have aged out as two requests" do
      # 1 fresh property (1 request) + 1 stale property (2 requests) = 3.
      create(:real_estate_property, facts_synced_at: 1.day.ago)
      create(:real_estate_property, facts_synced_at: (RealEstateProperty::FACTS_TTL + 1.day).ago)
      config.update!(requests_used: 48, quota_period_start: Date.current.beginning_of_month) # 2 left

      expect { described_class.perform_now }.not_to have_enqueued_job(RealEstate::RefreshJob)
    end

    it "runs when the allowance is exactly enough" do
      create(:real_estate_property, facts_synced_at: 1.day.ago)
      config.update!(requests_used: 49, quota_period_start: Date.current.beginning_of_month) # 1 left

      expect { described_class.perform_now }.to have_enqueued_job(RealEstate::RefreshJob).once
    end

    it "clears the quota issue once a run fits again" do
      Issue.raise_once!(key: quota_issue_key, title: "old")
      create(:real_estate_property, facts_synced_at: 1.day.ago)

      described_class.perform_now

      expect(Issue.active.where(key: quota_issue_key)).to be_empty
    end
  end

  it "stamps the last sync time" do
    create(:real_estate_property, facts_synced_at: 1.day.ago)

    described_class.perform_now

    expect(config.reload.last_synced_at).to be_present
  end
end
