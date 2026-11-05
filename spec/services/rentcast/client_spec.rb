require "rails_helper"

RSpec.describe Rentcast::Client do
  let!(:config) { create(:rentcast_configuration, api_key: "test-key") }

  def stub_value(status: 200, body: { price: 912_000 })
    stub_request(:get, "https://api.rentcast.io/v1/avm/value")
      .with(query: hash_including({}), headers: { "X-Api-Key" => "test-key" })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "#value_estimate" do
    it "returns the parsed estimate" do
      stub_value(body: { price: 912_000, priceRangeLow: 870_000, priceRangeHigh: 960_000 })

      result = described_class.new.value_estimate("5500 Grand Lake Dr")

      expect(result["price"]).to eq(912_000)
      expect(result["priceRangeHigh"]).to eq(960_000)
    end

    it "spends one request from the monthly allowance" do
      stub_value
      expect { described_class.new.value_estimate("x") }
        .to change { config.reload.requests_used }.by(1)
    end

    it "refuses to send a request once the allowance is gone" do
      config.update!(requests_used: 50, quota_period_start: Date.current.beginning_of_month)

      expect { described_class.new.value_estimate("x") }
        .to raise_error(RentcastConfiguration::QuotaExceeded)
      expect(a_request(:get, /rentcast/)).not_to have_been_made
    end

    it "raises NotFound on a 404 so callers can fall back to manual entry" do
      stub_value(status: 404, body: {})
      expect { described_class.new.value_estimate("nowhere") }.to raise_error(described_class::NotFound)
    end

    it "reports a rejected request without leaking internals" do
      stub_value(status: 401, body: {})
      expect { described_class.new.value_estimate("x") }
        .to raise_error(described_class::Error, /RentCast rejected the request/)
    end

    it "treats an upstream 429 as a quota problem, not a transient fault" do
      stub_value(status: 429, body: {})
      expect { described_class.new.value_estimate("x") }
        .to raise_error(RentcastConfiguration::QuotaExceeded)
    end
  end

  describe "#property_record" do
    it "normalizes a single-element array response to the record itself" do
      stub_request(:get, "https://api.rentcast.io/v1/properties")
        .with(query: hash_including({}))
        .to_return(status: 200, body: [ { id: "abc", formattedAddress: "1 Main St" } ].to_json,
                   headers: { "Content-Type" => "application/json" })

      expect(described_class.new.property_record("1 Main St")["id"]).to eq("abc")
    end

    it "raises NotFound when the response is empty" do
      stub_request(:get, "https://api.rentcast.io/v1/properties")
        .with(query: hash_including({}))
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      expect { described_class.new.property_record("nowhere") }.to raise_error(described_class::NotFound)
    end
  end

  describe ".build_query" do
    # URI.encode_www_form writes spaces as "+", which RentCast's address
    # parser reads literally — every lookup 400s with a valid key.
    it "percent-encodes spaces rather than form-encoding them" do
      query = described_class.build_query(address: "5500 Grand Lake Dr, San Antonio, TX, 78244")

      expect(query).to include("%20")
      expect(query).not_to include("+")
    end

    it "encodes each parameter" do
      expect(described_class.build_query(city: "San Antonio", state: "TX"))
        .to eq("city=San%20Antonio&state=TX")
    end
  end

  describe "#test_connection!" do
    it "checks credentials with a city lookup, so a geocoding miss can't fail it" do
      stub = stub_request(:get, "https://api.rentcast.io/v1/properties")
        .with(query: { city: "Austin", state: "TX", limit: "1" })
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      described_class.new.test_connection!

      expect(stub).to have_been_requested
    end
  end

  describe "error reporting" do
    it "passes RentCast's explanation through instead of swallowing it" do
      stub_value(status: 400, body: {
        status: 400, error: "resource/bad-request",
        message: "The provided address '1234 Main St' could not be parsed or geolocated"
      })

      expect { described_class.new.value_estimate("1234 Main St") }
        .to raise_error(described_class::Error, /could not be parsed or geolocated/)
    end

    it "names subscription and billing as 401 causes, not just a bad key" do
      stub_value(status: 401, body: {})

      expect { described_class.new.value_estimate("x") }
        .to raise_error(described_class::Error, /subscription status, and billing/)
    end

    it "surfaces the reason a 404 lookup missed" do
      stub_value(status: 404, body: { message: "No records found matching your query parameters" })

      expect { described_class.new.value_estimate("x") }
        .to raise_error(described_class::NotFound, /No records found/)
    end
  end

  it "refuses to build without a key" do
    config.update!(api_key: nil)
    expect { described_class.new }.to raise_error(ArgumentError, /not configured/)
  end
end
