require "rails_helper"

# Rack::Deflater is inserted outside Rack::ConditionalGet / Rack::ETag
# (config/application.rb) so JSON gzips regardless of the fronting nginx's
# config, while ETags stay computed over the uncompressed body.
RSpec.describe "Response compression", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  it "gzips JSON responses when the client accepts gzip" do
    get "/api/v1/benchmarks", headers: auth_headers.merge("Accept-Encoding" => "gzip")

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Encoding"]).to eq("gzip")

    body = Zlib::GzipReader.new(StringIO.new(response.body)).read
    symbols = JSON.parse(body).map { |b| b["symbol"] }
    expect(symbols).to include("SPY", "QQQ")
  end

  it "leaves responses uncompressed without Accept-Encoding" do
    get "/api/v1/benchmarks", headers: auth_headers

    expect(response.headers["Content-Encoding"]).to be_nil
    expect(response.parsed_body).to be_an(Array)
  end

  it "composes with the render_cached ETag flow: 304s pass through uncompressed" do
    get "/api/v1/net_worth", headers: auth_headers.merge("Accept-Encoding" => "gzip")
    etag = response.headers["ETag"]
    expect(etag).to be_present

    # The suite's null cache store regenerates the DataVersion per read, so
    # pin it to make the second request's ETag match the first.
    allow(Households::DataVersion).to receive(:current).and_return("pinned")
    get "/api/v1/net_worth", headers: auth_headers.merge("Accept-Encoding" => "gzip")
    etag = response.headers["ETag"]

    get "/api/v1/net_worth",
        headers: auth_headers.merge("Accept-Encoding" => "gzip", "If-None-Match" => etag)
    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_blank
    expect(response.headers["Content-Encoding"]).to be_nil
  end
end
