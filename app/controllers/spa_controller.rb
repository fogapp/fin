# typed: true

class SpaController < ApplicationController
  def index
    index_html = Rails.public_path.join("index.html")

    if index_html.exist?
      render file: index_html, layout: false, content_type: "text/html"
    else
      # Frontend hasn't been built yet (dev mode — use http://localhost:5173)
      render plain: <<~TEXT, status: :not_found, content_type: "text/plain"
        Frontend not built.
        In development: open http://localhost:5173
        In production:  run `cd frontend && npm run build`
      TEXT
    end
  end
end
