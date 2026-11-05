# typed: true

module Api
  module V1
    module Tiingo
      class ConfigurationsController < ProviderConfigurationController
        provider_configuration(
          configuration_class: TiingoConfiguration,
          params_key:          :tiingo_configuration,
          permitted:           [ :api_key ],
          display_name:        "Tiingo",
          client_errors:       [ "Tiingo::Error" ]
        )

        # Removing the integration re-routes its pinned instruments to the
        # next configured provider (Alpha Vantage / CoinGecko).
        def destroy
          TiingoConfiguration.current.destroy!
          MarketData::Router.repin_defaults!
          head :no_content
        end

        private

        def persist!(config)
          super
          # Candle routing prefers Tiingo while it's configured — re-evaluate
          # pins whenever the key appears or is cleared.
          MarketData::Router.repin_defaults!
        end

        # Tiingo's authenticated no-op endpoint — free and quota-less.
        def test_probe
          client = ::Tiingo::Client.new
          raise ::Tiingo::Error, "Unexpected response from Tiingo" unless client.test_connection
          { ok: true, message: "Connected — Tiingo accepted the API key" }
        end
      end
    end
  end
end
