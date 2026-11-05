# typed: true

module Middleware
  # Rewrites the public/ file server's far-future Cache-Control for the files
  # it isn't safe on.
  #
  # production.rb stamps everything ActionDispatch::Static serves with
  # `public, max-age=1.year`, on the assumption that those files are all digest
  # stamped. Only public/assets/** is — that's where Vite writes the hashed
  # bundles. The rest of public/ (index.html, fonts.css, icons.svg, the
  # favicons, public/fonts/*.woff2) keeps the same filename from build to
  # build, so a browser that cached one holds it for a year.
  #
  # index.html is the one that breaks the app outright. It names the hashed
  # entry bundle, and a container build writes a fresh public/assets, so an
  # index.html cached from the previous deploy points at chunks that no longer
  # exist. The entry script 404s, React never mounts, and the tab paints blank.
  # A normal reload doesn't recover it — the cached HTML is still fresh by
  # max-age, so the browser re-uses it without revalidating; only a hard
  # refresh does. (ErrorBoundary's chunk-load reload can't help here: nothing
  # has booted to catch the error.)
  #
  # So: HTML revalidates on every load, the other unstamped files get a short
  # TTL, and the digest-stamped bundles keep far-future caching.
  #
  # Inserted before ActionDispatch::Static (config/application.rb) so it sees
  # that middleware's responses on the way out. It only touches responses
  # carrying the configured static Cache-Control verbatim, which is what marks
  # them as having come from the file server rather than a controller.
  class StaticCacheControl
    DIGEST_STAMPED_PREFIX = "/assets/"
    HTML_EXTENSIONS = [ "", ".html" ].freeze
    UNSTAMPED_CACHE_CONTROL = "public, max-age=#{1.hour.to_i}"
    HTML_CACHE_CONTROL = "no-cache"

    def initialize(app, static_cache_control: nil)
      @app = app
      @static_cache_control = static_cache_control ||
        Rails.application.config.public_file_server.headers.to_h["cache-control"]
    end

    def call(env)
      status, headers, body = @app.call(env)
      rewrite(env["PATH_INFO"].to_s, headers)
      [ status, headers, body ]
    end

    private
      def rewrite(path, headers)
        return if @static_cache_control.blank?
        return unless headers["cache-control"] == @static_cache_control
        return if path.start_with?(DIGEST_STAMPED_PREFIX)

        # Keyed off the path, not the Content-Type: a 304 from the file server
        # carries the cache headers but no Content-Type. "/" (which resolves to
        # public/index.html) has no extension, hence the "" case.
        headers["cache-control"] =
          if HTML_EXTENSIONS.include?(File.extname(path))
            HTML_CACHE_CONTROL
          else
            UNSTAMPED_CACHE_CONTROL
          end
      end
  end
end
