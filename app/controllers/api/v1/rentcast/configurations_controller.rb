# typed: true

module Api
  module V1
    module Rentcast
      class ConfigurationsController < ProviderConfigurationController
        provider_configuration(
          configuration_class: RentcastConfiguration,
          params_key:          :rentcast_configuration,
          permitted:           [ :api_key, :monthly_request_limit ],
          display_name:        "RentCast",
          client_errors:       [ "Rentcast::Client::Error", "RentcastConfiguration::QuotaExceeded" ]
        )

        # Removing the integration leaves properties and their recorded
        # history in place — they simply stop updating automatically.
        def destroy
          RentcastConfiguration.current.destroy!
          head :no_content
        end

        private

        # RentCast has no free authenticated no-op endpoint, so proving the
        # key works costs one of the monthly requests. The UI says so on the
        # button.
        def test_probe
          client = ::Rentcast::Client.new(api_key: params[:api_key].presence)
          client.test_connection!
          { ok: true, message: "Connected — RentCast accepted the API key" }.merge(quota)
        end

        def serialized
          config = RentcastConfiguration.current
          {
            api_key_set:    config.api_key.present?,
            configured:     config.configured?,
            last_synced_at: config.last_synced_at,
            property_count: ::RealEstateProperty.owned.count
          }.merge(quota)
        end

        def quota
          config = RentcastConfiguration.current
          {
            quota: {
              used:         config.requests_used,
              limit:        config.monthly_request_limit,
              remaining:    config.remaining_quota,
              period_start: config.current_period_start,
              resets_on:    Date.current.next_month.beginning_of_month
            }
          }
        end
      end
    end
  end
end
