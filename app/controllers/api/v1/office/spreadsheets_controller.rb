# typed: true

module Api
  module V1
    module Office
      # Spreadsheets in the household's Office instance, read as a source of
      # transactions: pick one, check it against the spreadsheet layout, and
      # import a sheet of it into an account. The mirror image of
      # SheetExportsController, which writes Fin's tables out to Office.
      class SpreadsheetsController < BaseController
        rescue_from ::Office::Client::Error, with: :render_office_failed

        def index
          docs = client.list_spreadsheets(query: params[:query].presence)
          render json: docs.map { |doc| summary(doc) }
        end

        # The sheet checked as the import would read it, with the
        # spreadsheet's other sheets to choose from.
        def preview
          structure = client.sheet_structure(document_id)
          sheets    = visible_sheets(structure)
          sheet     = chosen_sheet(sheets)
          csv       = client.read_sheet_csv(document_id, sheet: sheet)

          render json: summary(structure).merge(
            sheets:  sheets.map { |s| { name: s["name"], used_range: s["used_range"] } },
            sheet:   sheet,
            preview: Importers::Preview.new(csv: csv, account: account).call
          )
        end

        def import
          raise ActionController::BadRequest, "account_id is required" if account.nil?

          structure = client.sheet_structure(document_id)
          sheet     = chosen_sheet(visible_sheets(structure))
          csv       = client.read_sheet_csv(document_id, sheet: sheet)
          title     = structure["title"].presence || "Office spreadsheet #{document_id}"

          import = CsvImport.new(
            source_filename: [ title, sheet ].compact.join(" › "),
            target_account:  account,
            status:          :pending
          )
          import.file.attach(io: StringIO.new(csv), filename: "#{title.parameterize.presence || 'office-sheet'}.csv", content_type: "text/csv")
          import.save!

          Importers::Runner.run!(import)
          render json: Api::Render::Import.new.serialize(import), status: import.failed? ? :unprocessable_content : :created
        end

        private

        def client
          @client ||= ::Office::Client.new
        end

        def document_id
          Integer(params[:id])
        rescue ArgumentError
          raise ActionController::BadRequest, "id must be an Office document id"
        end

        def account
          return @account if defined?(@account)

          @account = params[:account_id].present? ? Account.find(params[:account_id]) : nil
        end

        def summary(doc)
          {
            id:         doc["id"],
            title:      doc["title"],
            folder:     doc["folder"],
            updated_at: doc["updated_at"],
            url:        doc["id"] ? client.document_url(Integer(doc["id"])) : nil
          }
        end

        def visible_sheets(structure)
          Array(structure["sheets"]).grep(Hash).reject { |s| s["hidden"] }
        end

        # The sheet asked for, else the one the spreadsheet opens on.
        def chosen_sheet(sheets)
          asked = params[:sheet].presence
          return asked if asked && sheets.any? { |s| s["name"] == asked }
          raise ActionController::BadRequest, "No sheet named “#{asked}” in this spreadsheet" if asked

          (sheets.find { |s| s["active"] } || sheets.first)&.dig("name")
        end

        # Office unreachable or refusing is the upstream's problem — 502, with
        # the message already written for a person.
        def render_office_failed(exception)
          render json: { error: exception.message, errors: [ exception.message ] }, status: :bad_gateway
        end
      end
    end
  end
end
