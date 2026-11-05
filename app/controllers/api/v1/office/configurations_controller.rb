# typed: true

module Api
  module V1
    module Office
      # The Office connection, as Settings → Integrations edits it: the
      # instance's URL, an API token minted there, and optionally the folder
      # new spreadsheets are filed in.
      #
      # Unlike the market-data providers this one is not a data source — it's
      # a destination — but the credential lifecycle is identical, so it uses
      # the same show/update/test/destroy skeleton.
      class ConfigurationsController < ProviderConfigurationController
        provider_configuration(
          configuration_class: OfficeConfiguration,
          params_key:          :office_configuration,
          permitted:           [ :base_url, :api_key, :default_folder_id ],
          display_name:        "Office",
          client_errors:       [ "Office::Client::Error" ]
        )

        # Removing the connection leaves every spreadsheet in Office
        # untouched; Fin just forgets how to reach them. The links are
        # dropped too, since a stale sheet list nobody can refresh is worse
        # than an empty one.
        def destroy
          OfficeSheetExport.destroy_all
          OfficeConfiguration.current.destroy!
          head :no_content
        end

        private

        # A save may point Fin at a different instance, where the document
        # ids it recorded mean nothing — or nothing at all. Only the token
        # and folder can change without invalidating the links.
        def persist!(config)
          previous = config.resolved_base_url
          config.assign_attributes(configuration_params)
          config.save!
          OfficeSheetExport.destroy_all if previous.present? && previous != config.resolved_base_url
        end

        def test_probe
          tools = ::Office::Client.new.test_connection!
          { ok: true, message: "Connected to Office", tools: tools["tools"] }
        end

        def serialized
          config = OfficeConfiguration.current
          {
            configured:        config.configured?,
            api_key_set:       config.resolved_api_key.present?,
            base_url:          config.resolved_base_url,
            default_folder_id: config.default_folder_id,
            # Which of the two sources is supplying the connection, so the
            # settings pane can say "set in the environment" rather than
            # showing an empty form beside a working integration.
            source:            credential_source(config),
            datasets:          ::Office::Datasets.all.values.map { |d| { key: d.key, label: d.label } },
            sheet_count:       OfficeSheetExport.count
          }
        end

        def credential_source(config)
          return "configuration" if config.api_key.present?
          return "environment"   if ENV["OFFICE_API_TOKEN"].present?

          nil
        end
      end
    end
  end
end
