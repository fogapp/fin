# typed: true

module Api
  module V1
    module Alchemy
      class ConfigurationsController < ProviderConfigurationController
        provider_configuration(
          configuration_class: AlchemyConfiguration,
          params_key:          :alchemy_configuration,
          permitted:           [ :api_key, :auth_token, :webhook_base_url,
                                 :transactions_enabled, :sync_frequency ],
          display_name:        "Alchemy",
          # Our own client's formatted message, or ArgumentError for missing
          # credentials. Both already user-facing.
          client_errors:       [ "AlchemyClient::Error", "ArgumentError" ]
        )

        private

        def persist!(config)
          was_configured  = config.configured?
          was_txn_enabled = config.transactions_enabled?
          super
          orchestrator.configuration_changed(config, was_configured: was_configured, was_txn_enabled: was_txn_enabled)
        end

        def orchestrator = ::Alchemy::Orchestrator.new(Current.household!.id)

        def test_probe
          AlchemyClient.new.test_connection!
          { ok: true, message: "Connected to Alchemy" }
        end

        def configuration_params
          permitted = super
          if permitted[:sync_frequency].present?
            # 422 listing the allowed values instead of a model validation error.
            AlchemyConfiguration::SyncFrequency.try_deserialize(permitted[:sync_frequency].to_s) || raise(
              InvalidEnumParam,
              "sync_frequency must be one of: " \
              "#{AlchemyConfiguration::SyncFrequency.values.map(&:serialize).join(', ')}"
            )
          end
          permitted
        end

        def serialized
          config = AlchemyConfiguration.current
          {
            api_key_set:                 config.api_key.present?,
            configured:                  config.configured?,
            transactions_enabled:        config.transactions_enabled?,
            sync_frequency:              config.sync_frequency.to_s,
            auth_token_set:              config.auth_token.present?,
            webhook_base_url:            config.webhook_base_url,
            suggested_webhook_base_url:  request.base_url,
            transactions_last_synced_at: config.transactions_last_synced_at&.iso8601,
            webhooks: AlchemyWebhook.order(:network).map do |w|
              {
                network:          w.network,
                status:           w.status.to_s,
                last_received_at: w.last_received_at&.iso8601,
                last_error:       w.last_error
              }
            end
          }
        end
      end
    end
  end
end
