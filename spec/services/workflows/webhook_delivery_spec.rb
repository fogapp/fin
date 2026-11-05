require "rails_helper"

RSpec.describe Workflows::WebhookDelivery do
  let(:url) { "https://hooks.example.test/in" }

  it "posts the payload as JSON and reports a 2xx as delivered" do
    stub = stub_request(:post, url).with(body: { "a" => 1 }.to_json).to_return(status: 204)
    expect(described_class.post(url, { a: 1 })).to eq(status: "delivered", code: 204)
    expect(stub).to have_been_requested
  end

  it "reports a non-2xx as rejected without following redirects" do
    stub_request(:post, url).to_return(status: 302, headers: { "Location" => "https://elsewhere.test" })
    expect(described_class.post(url, {})).to eq(status: "rejected", code: 302)
  end

  it "refuses plain http" do
    expect { described_class.post("http://hooks.example.test/in", {}) }.to raise_error(ArgumentError, /https/)
  end

  it "raises its own error on a network failure" do
    stub_request(:post, url).to_timeout
    expect { described_class.post(url, {}) }.to raise_error(described_class::Error)
  end
end
