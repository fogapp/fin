require "rails_helper"

RSpec.describe CoinbaseSyncTickJob, type: :job do
  it "enqueues the household sync when Coinbase is configured" do
    CoinbaseConfiguration.create!(api_key_id: "k", api_key_secret: "s")

    expect { described_class.perform_now }
      .to have_enqueued_job(CoinbaseSyncJob).with(Current.household.id)
  end

  it "enqueues the household sync when the credentials exist only in ENV" do
    with_env("COINBASE_API_KEY_ID" => "env-id", "COINBASE_API_KEY_SECRET" => "env-secret") do
      expect { described_class.perform_now }
        .to have_enqueued_job(CoinbaseSyncJob).with(Current.household.id)
    end
  end

  it "skips households without Coinbase credentials" do
    with_env("COINBASE_API_KEY_ID" => nil, "COINBASE_API_KEY_SECRET" => nil) do
      expect { described_class.perform_now }.not_to have_enqueued_job(CoinbaseSyncJob)
    end
  end
end
