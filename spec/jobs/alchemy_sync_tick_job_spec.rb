require "rails_helper"

RSpec.describe AlchemySyncTickJob, type: :job do
  it "enqueues the household sync when Alchemy is configured" do
    create(:alchemy_configuration)

    expect { described_class.perform_now }
      .to have_enqueued_job(AlchemySyncJob).with(Current.household.id)
  end

  it "skips households without an Alchemy API key" do
    expect { described_class.perform_now }.not_to have_enqueued_job(AlchemySyncJob)
  end
end
