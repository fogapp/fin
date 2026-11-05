require "rails_helper"

RSpec.describe "SpaController", type: :request do
  describe "GET /" do
    it "renders public/index.html with text/html when the frontend has been built" do
      expect(Rails.public_path.join("index.html")).to exist

      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end

    it "renders dev-mode instructions with 404 when index.html is missing" do
      empty_dir = Pathname.new(Dir.mktmpdir)
      allow(Rails).to receive(:public_path).and_return(empty_dir)

      # Route to a non-/ path so ActionDispatch::Static doesn't intercept and
      # serve the real index.html before the controller runs.
      get "/some/client/route"
      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to include("Frontend not built", "http://localhost:5173")
    ensure
      FileUtils.remove_entry(empty_dir) if empty_dir
    end
  end

  describe "SPA catch-all" do
    it "serves the SPA for unknown non-API paths" do
      get "/some/client/route"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end
  end
end
