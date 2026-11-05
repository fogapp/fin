# typed: true

module Api
  module V1
    class SavedReportsController < BaseController
      renders_with Api::Render::SavedReport

      def index
        render json: renderer.index
      end

      def create
        report = SavedReport.new(
          name:   params.require(:name).to_s.strip,
          # Arbitrary page-state blob; the frontend owns its shape. to_unsafe_h
          # is safe here because the value is stored and echoed, never used to
          # build a query.
          config: params.require(:config).to_unsafe_h.to_json
        )
        report.save!
        render json: renderer.serialize(report), status: :created
      end

      def destroy
        SavedReport.find(params[:id]).destroy!
        head :no_content
      end
    end
  end
end
