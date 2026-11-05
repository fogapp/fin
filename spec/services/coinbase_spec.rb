require "rails_helper"

RSpec.describe Coinbase do
  around do |ex|
    with_env("COINBASE_API_KEY_ID" => nil, "COINBASE_API_KEY_SECRET" => nil) { ex.run }
  end

  it "uses the household's configured credentials" do
    CoinbaseConfiguration.create!(api_key_id: "id", api_key_secret: "secret")

    expect(described_class.credentials.to_h).to eq(key_id: "id", key_secret: "secret")
    expect(described_class).to be_configured
  end

  it "falls back to ENV credentials" do
    with_env("COINBASE_API_KEY_ID" => "env-id", "COINBASE_API_KEY_SECRET" => "env-secret") do
      expect(described_class.credentials.to_h).to eq(key_id: "env-id", key_secret: "env-secret")
      expect(described_class).to be_configured
    end
  end

  it "is unconfigured when either half is missing" do
    with_env("COINBASE_API_KEY_ID" => "env-id") do
      expect(described_class.credentials).to be_nil
      expect(described_class).not_to be_configured
    end
  end
end
