# ApplicationController calls `allow_browser versions: :modern`, which checks
# the User-Agent header against a list of modern browser versions. Rack::Test
# defaults to no UA, which fails the check and returns 406. This shim sets a
# modern Chrome UA on every request spec.
RSpec.configure do |config|
  config.before(:each, type: :request) do
    Rack::Test::Methods.module_eval do
      # noop — we just need the methods loaded
    end
  end

  config.around(:each, type: :request) do |example|
    @_default_headers ||= { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" }
    example.run
  end
end

module ModernBrowserRequestHelper
  MODERN_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36".freeze

  %i[get post patch put delete].each do |verb|
    define_method(verb) do |path, **opts|
      headers = (opts[:headers] || {}).reverse_merge("User-Agent" => MODERN_UA)
      super(path, **opts.merge(headers: headers))
    end
  end
end

RSpec.configure do |config|
  config.include ModernBrowserRequestHelper, type: :request
end
