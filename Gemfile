source "https://rubygems.org"

gem "rails", "~> 8.1.4", ">= 8.1.4.1"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "dotenv", groups: [ :development, :test ]

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache and Active Job
gem "solid_cache"
gem "solid_queue"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false


# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# CSV parsing for the importers. A bundled (not default) gem since Ruby 3.4,
# so it has to be declared to be loadable under Bundler.
gem "csv"

# Time-series grouping for analytics queries
gem "groupdate"

# Plaid bank account integration
gem "plaid"

# Passkey (WebAuthn) authentication.
#
# require: false — webauthn drags in five attestation/COSE gems (tpm-key_
# attestation, safety_net_attestation, android_key_attestation, cose, bindata)
# for ~12 MB of heap, and only the two passkey controllers ever touch it.
# WebauthnRelyingParty requires it in a before_action, so the worker container
# and every non-passkey request boot without it.
gem "webauthn", "~> 3.5", require: false

# API documentation
gem "rswag-api"
gem "rswag-ui"
# ostruct left Ruby's default gems in 4.0; rswag-ui 2.17 requires it
# without declaring it. Drop this once rswag-ui lists the dependency itself.
gem "ostruct"

# Static typing runtime (T::, T.sig, T::Enum)
gem "sorbet-runtime"

# Error reporting to Fog's built-in tracker. Vendored (synced from
# fog:clients/flare) so Docker builds need no gem host; inert without the
# FLARE_DSN env Fog injects, so dev/test are unaffected.
gem "flare", path: "vendor/gems/flare"

# Metrics, traces, profiles, logs and browser analytics to Glass. Vendored
# (synced from glass:clients/ruby); must follow gem "rails" so its railtie
# loads. Inert without GLASS_URL + GLASS_API_KEY, so dev/test are unaffected.
gem "glass", path: "vendor/gems/glass"

# The app-side view of fog (synced from fog:clients/fog-client), here for
# household sign-in (FogClient::Signin, fog:docs/signin-proposal.md §15).
# Inert without OIDC_ISSUER/OIDC_CLIENT_ID/OIDC_CLIENT_SECRET. Explicit
# require: the gem's entry file is fog_client.rb, which Bundler's default
# (require "fog-client") silently misses.
gem "fog-client", path: "vendor/gems/fog-client", require: "fog_client"

# Model Context Protocol server (POST /mcp).
#
# require: false — the gem pulls json_schemer (~7 MB of heap) and is only
# reachable through McpController. Mcp::Tools::Base requires it (it subclasses
# ::MCP::Tool), and app/domain/mcp is excluded from eager loading in
# application.rb so that require stays lazy.
gem "mcp", "~> 1.9", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.4"
  gem "rswag-specs"
end

group :test do
  gem "shoulda-matchers", "~> 7.0"
  gem "webmock", "~> 3.34"
  gem "simplecov", "~> 1.2", require: false
end

group :development do
  gem "web-console"
  gem "sorbet",        require: false
  gem "tapioca",       require: false
  gem "rubocop-sorbet", require: false
end
