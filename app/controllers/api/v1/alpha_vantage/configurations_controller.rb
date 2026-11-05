# typed: true

module Api
  module V1
    module AlphaVantage
      class ConfigurationsController < ProviderConfigurationController
        provider_configuration(
          configuration_class: AlphaVantageConfiguration,
          params_key:          :alpha_vantage_configuration,
          permitted:           [ :api_key ],
          display_name:        "Alpha Vantage",
          log_tag:             "AlphaVantage",
          client_errors:       [ "AlphaVantage::Error" ]
        )

        private

        # Cheapest authenticated probe on the free tier: a symbol search.
        def test_probe
          client = ::AlphaVantage::Client.new
          matches = client.symbol_search("AAPL")
          raise ::AlphaVantage::Error, "No matches returned" if matches.empty?
          { ok: true, message: "Connected — symbol search returned #{matches.size} matches" }
        end
      end
    end
  end
end
