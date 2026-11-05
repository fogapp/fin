# typed: true

module Api
  module V1
    class ImportsController < BaseController
      renders_with Api::Render::Import

      def create
        file = params[:file]
        raise ActionController::BadRequest, "file is required" if file.blank?

        account = params[:account_id].present? ? Account.find(params[:account_id]) : nil
        broker  = params[:broker_id].present?  ? Broker.find(params[:broker_id])   : nil

        import = CsvImport.new(
          source_filename: file.original_filename,
          broker_name:     broker&.name,
          target_account:  account,
          status:          :pending
        )
        import.file.attach(file)
        import.save!

        Importers::Runner.run!(import)
        status = import.failed? ? :unprocessable_content : :created
        render json: renderer.serialize(import), status: status
      end

      # Checks a file without importing it: its format, missing columns,
      # and the rows that won't import.
      def preview
        file = params[:file]
        raise ActionController::BadRequest, "file is required" if file.blank?

        account = params[:account_id].present? ? Account.find(params[:account_id]) : nil
        render json: Importers::Preview.new(csv: file.read, account: account).call
      end

      # The spreadsheet layout, for the modal's "how to format your sheet".
      def spreadsheet_format
        render json: Importers::SpreadsheetFormat.describe
      end
    end
  end
end
