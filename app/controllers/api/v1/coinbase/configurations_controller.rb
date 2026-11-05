# typed: true

module Api
  module V1
    module Coinbase
      class ConfigurationsController < ProviderConfigurationController
        provider_configuration(
          configuration_class: CoinbaseConfiguration,
          params_key:          :coinbase_configuration,
          permitted:           [ :api_key_id, :api_key_secret ],
          display_name:        "Coinbase",
          # CoinbaseClient::Error is formatted "Coinbase <code>: <error>";
          # ArgumentError covers missing credentials. Both already user-facing.
          client_errors:       [ "CoinbaseClient::Error", "ArgumentError" ]
        )

        private

        def persist!(config)
          was_configured = config.configured?
          super
          CoinbaseSyncJob.perform_later(Current.household.id) if !was_configured && config.configured?
        end

        def test_probe
          count = CoinbaseClient.new.accounts(limit: 10).length
          { ok: true, message: "Connected — #{count} account(s) found" }
        end

        def serialized
          config = CoinbaseConfiguration.current
          {
            api_key_id_set:     config.api_key_id.present?,
            api_key_secret_set: config.api_key_secret.present?,
            configured:         config.configured?
          }
        end
      end
    end
  end
end
