# typed: true

module Api
  module V1
    module Plaid
      class ConfigurationsController < ProviderConfigurationController
        provider_configuration(
          configuration_class: PlaidConfiguration,
          params_key:          :plaid_configuration,
          permitted:           [ :client_id, :secret, :environment ],
          display_name:        "Plaid"
        )

        private

        # Plaid config is per-household rather than a `.current` singleton.
        def configuration
          Current.household.plaid_configurations.first_or_initialize
        end

        def serialized
          config = Current.household.plaid_configurations.first_or_initialize(
            environment: ENV.fetch("PLAID_ENV", "production")
          )
          via_env = ENV["PLAID_CLIENT_ID"].present? && ENV["PLAID_SECRET"].present?
          configured = config.configured? || via_env || ::PlaidItem.exists?
          {
            environment:    config.environment,
            client_id_set:  config.client_id.present? || ENV["PLAID_CLIENT_ID"].present?,
            secret_set:     config.secret.present?    || ENV["PLAID_SECRET"].present?,
            configured:     configured,
            source:         config.persisted? && config.configured? ? "database" : "environment"
          }
        end
      end
    end
  end
end
