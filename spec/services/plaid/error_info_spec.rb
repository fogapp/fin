require "rails_helper"

RSpec.describe Plaid::ErrorInfo do
  def api_error(body)
    Plaid::ApiError.new(code: 400, response_body: body.is_a?(String) ? body : body.to_json)
  end

  def info(body) = described_class.from(api_error(body))

  it "reads the code, type and integrator-facing message from the body" do
    parsed = info("error_type" => "ITEM_ERROR", "error_code" => "ITEM_LOGIN_REQUIRED", "error_message" => "log in again")
    expect([ parsed.type, parsed.code, parsed.message ]).to eq([ "ITEM_ERROR", "ITEM_LOGIN_REQUIRED", "log in again" ])
  end

  it "tolerates a body that isn't JSON" do
    parsed = info("<html>bad gateway</html>")
    expect([ parsed.parsed?, parsed.code, parsed.message ]).to eq([ false, "", nil ])
  end

  describe "#skippable_product_error?" do
    it "skips products the item can't serve, rate limits and consent problems" do
      expect(info("error_code" => "PRODUCT_NOT_READY")).to be_skippable_product_error
      expect(info("error_type" => "RATE_LIMIT_EXCEEDED")).to be_skippable_product_error
      expect(info("error_message" => "Additional Consent is needed")).to be_skippable_product_error
    end

    it "does not skip other errors" do
      expect(info("error_code" => "INTERNAL_SERVER_ERROR")).not_to be_skippable_product_error
    end
  end

  describe "#retriable?" do
    it "does not retry errors that need the user to re-link or re-consent" do
      expect(info("error_type" => "ITEM_ERROR")).not_to be_retriable
      expect(info("error_code" => "INVALID_ACCESS_TOKEN")).not_to be_retriable
      expect(info("error_message" => "user revoked consent")).not_to be_retriable
    end

    it "retries everything else, including unparseable bodies" do
      expect(info("error_type" => "API_ERROR", "error_code" => "INTERNAL_SERVER_ERROR")).to be_retriable
      expect(info("oops")).to be_retriable
    end
  end
end
