# typed: true

module Api
  module V1
    class SavedViewsController < BaseController
      renders_with Api::Render::SavedView

      def index
        render json: renderer.index
      end

      def create
        view = SavedView.new(
          name:          params.require(:name).to_s.strip,
          filter_params: build_filter_params.to_json
        )
        view.save!
        render json: renderer.serialize(view), status: :created
      end

      def update
        view = SavedView.find(params[:id])
        view.update!(
          name:          params[:name].to_s.strip.presence || view.name,
          filter_params: build_filter_params.to_json
        )
        render json: renderer.serialize(view)
      end

      def destroy
        SavedView.find(params[:id]).destroy!
        head :no_content
      end

      private

      def build_filter_params
        {
          conditions:     params[:conditions],
          match_all:      params[:match_all],
          group_by:       params[:group_by],
          primary_sort:   params[:primary_sort],
          secondary_sort: params[:secondary_sort]
        }
      end
    end
  end
end
