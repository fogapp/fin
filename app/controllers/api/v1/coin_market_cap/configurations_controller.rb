# typed: true

module Api
  module V1
    module CoinMarketCap
      class ConfigurationsController < ProviderConfigurationController
        provider_configuration(
          configuration_class: CoinMarketCapConfiguration,
          params_key:          :coin_market_cap_configuration,
          permitted:           [ :api_key ],
          display_name:        "CoinMarketCap",
          log_tag:             "CMC",
          client_errors:       [ "CoinMarketCap::Error" ]
        )

        private

        def test_probe
          client = ::CoinMarketCap::Client.new
          prices = client.quotes([ "BTC" ])
          raise ::CoinMarketCap::Error, "No price returned" unless prices["BTC"]
          { ok: true, message: "Connected — BTC is $#{prices['BTC'].round(2)}" }
        end
      end
    end
  end
end
