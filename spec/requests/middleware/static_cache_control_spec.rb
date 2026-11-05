require "rails_helper"

# Middleware::StaticCacheControl (config/application.rb) rewrites the public/
# file server's far-future Cache-Control for the files that aren't digest
# stamped. The bug it fixes: a year-cached index.html names hashed bundles that
# a later build deleted, so the SPA's entry script 404s and the page paints
# blank until a hard refresh.
RSpec.describe "Static cache control", type: :request do
  let(:static_cache_control) { Rails.application.config.public_file_server.headers.to_h["cache-control"] }
  let(:digest_stamped_asset) do
    Dir.children(Rails.public_path.join("assets")).find { |f| f.end_with?(".js") }
  end

  it "makes the SPA document revalidate on every load" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.headers["cache-control"]).to eq("no-cache")
  end

  it "makes index.html revalidate when it is requested by name" do
    get "/index.html"

    expect(response).to have_http_status(:ok)
    expect(response.headers["cache-control"]).to eq("no-cache")
  end

  # "no-cache" means revalidate, not re-download: the file server answers a
  # conditional request from its own Last-Modified, so the usual case costs a
  # round trip and an empty body rather than the document.
  it "still answers a conditional request for the SPA document with a 304" do
    get "/"
    last_modified = response.headers["last-modified"]
    expect(last_modified).to be_present

    get "/", headers: { "If-Modified-Since" => last_modified }

    expect(response).to have_http_status(:not_modified)
  end

  it "leaves the digest-stamped bundles on far-future caching" do
    get "/assets/#{digest_stamped_asset}"

    expect(response).to have_http_status(:ok)
    expect(response.headers["cache-control"]).to eq(static_cache_control)
  end

  it "gives the unstamped static files a short TTL" do
    get "/fonts.css"

    expect(response).to have_http_status(:ok)
    expect(response.headers["cache-control"]).to eq(Middleware::StaticCacheControl::UNSTAMPED_CACHE_CONTROL)
  end

  it "leaves controller-rendered responses alone" do
    get "/some/client/route"

    expect(response).to have_http_status(:ok)
    expect(response.headers["cache-control"]).to eq("max-age=0, private, must-revalidate")
  end
end
