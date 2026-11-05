require "rails_helper"

RSpec.describe PlaidConfiguration do
  describe ".default_environment" do
    around do |example|
      original = ENV["PLAID_ENV"]
      example.run
    ensure
      ENV["PLAID_ENV"] = original
    end

    it "uses PLAID_ENV when set" do
      ENV["PLAID_ENV"] = "sandbox"
      expect(described_class.default_environment).to eq("sandbox")
    end

    it "treats the retired development stack as production" do
      ENV["PLAID_ENV"] = "development"
      expect(described_class.default_environment).to eq("production")
    end

    it "falls back to sandbox outside production" do
      ENV.delete("PLAID_ENV")
      expect(described_class.default_environment).to eq("sandbox")
    end

    it "falls back to production in a production deployment" do
      ENV.delete("PLAID_ENV")
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(described_class.default_environment).to eq("production")
    end
  end
end
