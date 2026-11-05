# typed: true

module Api
  module V1
    module Office
      # The spreadsheets this household keeps in Office, and the two things
      # you can do to them from Fin: make one from a datatable, and push
      # fresh rows into one that already exists.
      class SheetExportsController < BaseController
        renders_with Api::Render::OfficeSheetExport

        rescue_from ::Office::Exporter::Error, with: :render_export_failed

        def index
          render json: renderer.index
        end

        def create
          export = ::Office::Exporter.new.create(
            dataset:    params.require(:dataset),
            params:     params,
            visibility: params[:visibility].presence,
            folder_id:  params[:folder_id].presence&.to_i
          )
          render json: renderer.serialize(export), status: :created
        end

        def refresh
          export = ::OfficeSheetExport.find(params[:id])
          render json: renderer.serialize(::Office::Exporter.new.refresh(export))
        end

        # Forgets the link. The spreadsheet stays in Office untouched —
        # deleting someone's document because Fin stopped tracking it
        # would be a surprise, and Office has its own trash for that.
        def destroy
          ::OfficeSheetExport.find(params[:id]).destroy!
          head :no_content
        end

        private

        # Office being unreachable, refusing the token, or refusing the
        # write is the upstream's problem, not a malformed request — 502
        # says so, and the message is already user-facing.
        def render_export_failed(exception)
          render json: { error: exception.message, errors: [ exception.message ] }, status: :bad_gateway
        end
      end
    end
  end
end
