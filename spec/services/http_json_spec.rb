require "rails_helper"

RSpec.describe HttpJson do
  let(:uri) { URI("https://api.example.test/things") }
  let(:error_class) { Class.new(StandardError) }
  let(:rate_limit_class) { Class.new(error_class) }
  let(:auth_class) { Class.new(error_class) }

  def call(**opts)
    described_class.request(:get, uri, error: error_class, label: "Example", **opts)
  end

  describe ".request" do
    it "returns the parsed body on success" do
      stub_request(:get, uri.to_s).to_return(status: 200, body: { "ok" => true }.to_json)
      expect(call).to eq("ok" => true)
    end

    it "sends headers and JSON-encodes a non-string body" do
      stub = stub_request(:post, uri.to_s)
        .with(body: { "a" => 1 }.to_json, headers: { "X-Key" => "k" })
        .to_return(status: 200, body: "{}")
      described_class.request(:post, uri, error: error_class, label: "Example",
                                          headers: { "X-Key" => "k" }, body: { a: 1 })
      expect(stub).to have_been_requested
    end

    it "checks the status before parsing, so an HTML 429 still raises the rate-limit error" do
      stub_request(:get, uri.to_s).to_return(status: 429, body: "<html>slow down</html>")
      expect { call(rate_limit_error: rate_limit_class) }.to raise_error(rate_limit_class, /Example 429: <html>slow down/)
    end

    it "falls back to the base error for a 429 when no rate-limit error is given" do
      stub_request(:get, uri.to_s).to_return(status: 429, body: "")
      expect { call }.to raise_error(error_class, /Example 429/)
    end

    it "raises the auth error on 401/403 when given" do
      stub_request(:get, uri.to_s).to_return(status: 403, body: "nope")
      expect { call(auth_error: auth_class) }.to raise_error(auth_class, /Example 403: nope/)
    end

    it "uses the detail extractor for the message" do
      stub_request(:get, uri.to_s).to_return(status: 500, body: { "error" => { "message" => "boom" } }.to_json)
      expect { call(detail: ->(r) { r.json_object.dig("error", "message") }) }
        .to raise_error(error_class, "Example 500: boom")
    end

    it "raises on a non-JSON success body" do
      stub_request(:get, uri.to_s).to_return(status: 200, body: "<html>")
      expect { call }.to raise_error(error_class, /non-JSON/)
    end

    it "returns {} for an empty success body when allowed" do
      stub_request(:get, uri.to_s).to_return(status: 204, body: "")
      expect(call(allow_empty: true)).to eq({})
    end

    it "maps network failures to the client's error" do
      stub_request(:get, uri.to_s).to_timeout
      expect { call }.to raise_error(error_class, /Example request failed/)
    end
  end

  describe ".perform" do
    it "returns non-2xx responses without raising" do
      stub_request(:get, uri.to_s).to_return(status: 404, body: "gone")
      response = described_class.perform(:get, uri, error: error_class, label: "Example")
      expect([ response.success?, response.code, response.body, response.json ]).to eq([ false, "404", "gone", nil ])
    end

    it "uses a custom network message when given" do
      stub_request(:get, uri.to_s).to_raise(SocketError)
      expect {
        described_class.perform(:get, uri, error: error_class, label: "Example",
                                           network_message: ->(_e) { "could not reach it" })
      }.to raise_error(error_class, "could not reach it")
    end
  end
end
