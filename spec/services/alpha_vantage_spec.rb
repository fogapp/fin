require "rails_helper"

RSpec.describe AlphaVantage do
  let(:household) { create(:household) }

  around do |example|
    original = ENV["ALPHA_VANTAGE_API_KEY"]
    ENV.delete("ALPHA_VANTAGE_API_KEY")
    example.run
  ensure
    original.nil? ? ENV.delete("ALPHA_VANTAGE_API_KEY") : ENV["ALPHA_VANTAGE_API_KEY"] = original
  end

  describe ".api_key" do
    it "is nil when nothing is configured" do
      expect(described_class.api_key).to be_nil
      expect(described_class.configured?).to be false
    end

    it "uses the current household's configuration first" do
      other = create(:household)
      AlphaVantageConfiguration.create!(api_key: "other-key", household: other, created_at: 1.year.ago)
      AlphaVantageConfiguration.create!(api_key: "mine", household: household)

      Current.set(household: household) do
        expect(described_class.api_key).to eq("mine")
      end
    end

    it "falls back to any configured household outside a household context" do
      AlphaVantageConfiguration.create!(api_key: "shared-key", household: household)

      Current.set(household: nil) do
        expect(described_class.api_key).to eq("shared-key")
        expect(described_class.configured?).to be true
      end
    end

    it "resolves deterministically to the oldest configuration" do
      newer = create(:household)
      AlphaVantageConfiguration.create!(api_key: "first", household: household, created_at: 2.years.ago)
      AlphaVantageConfiguration.create!(api_key: "second", household: newer, created_at: 1.year.ago)

      Current.set(household: nil) do
        expect(described_class.api_key).to eq("first")
      end
    end

    it "falls back to ENV when no configuration has a key" do
      ENV["ALPHA_VANTAGE_API_KEY"] = "env-key"
      expect(described_class.api_key).to eq("env-key")
    end

    it "prefers a stored configuration over ENV" do
      ENV["ALPHA_VANTAGE_API_KEY"] = "env-key"
      AlphaVantageConfiguration.create!(api_key: "db-key", household: household)
      expect(described_class.api_key).to eq("db-key")
    end

    it "skips a household configuration without a key" do
      AlphaVantageConfiguration.create!(api_key: nil, household: household)
      Current.set(household: household) do
        expect(described_class.api_key).to be_nil
      end
    end
  end
end
