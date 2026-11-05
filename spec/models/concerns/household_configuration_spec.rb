require "rails_helper"

RSpec.describe HouseholdConfiguration do
  let(:household) { create(:household) }

  describe ".current" do
    it "raises Current::NoHousehold outside a household context" do
      Current.set(household: nil) do
        expect { TiingoConfiguration.current }.to raise_error(Current::NoHousehold)
      end
    end

    it "returns the household's row, building one when absent" do
      Current.set(household: household) do
        config = TiingoConfiguration.current
        expect(config).to be_new_record
        expect(config.household_id).to eq(household.id)

        config.update!(api_key: "k")
        expect(TiingoConfiguration.current).to eq(config)
      end
    end

    it "applies the includer's defaults to a new row" do
      Current.set(household: household) do
        expect(PlaidConfiguration.current.environment.serialize).to eq(PlaidConfiguration.default_environment)
      end
    end
  end

  describe "#configured?" do
    it "requires every configured_when attribute" do
      expect(CoinbaseConfiguration.new(api_key_id: "id").configured?).to be(false)
      expect(CoinbaseConfiguration.new(api_key_id: "id", api_key_secret: "s").configured?).to be(true)
    end
  end
end
