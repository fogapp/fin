# typed: true

module Api
  module V1
    class CategoriesController < BaseController
      renders_with Api::Render::Category

      def index
        render json: renderer.index
      end

      def show
        render json: renderer.show
      end

      def create
        category = Category.new(name: params[:name].to_s.strip, parent_id: params[:parent_id].presence)
        category.charitable = params[:charitable] if params.key?(:charitable)
        category.save!
        render json: renderer.serialize(category), status: :created
      end

      def update
        category = Category.find(params[:id])
        attrs = {}
        attrs[:name] = params[:name].to_s.strip if params.key?(:name)
        attrs[:parent_id] = params[:parent_id].presence if params.key?(:parent_id)
        attrs[:budget_kind] = params[:budget_kind] if params.key?(:budget_kind)
        attrs[:charitable] = params[:charitable] if params.key?(:charitable)
        category.update!(attrs)
        render json: renderer.serialize(category)
      end

      def destroy
        Category.find(params[:id]).destroy!
        head :no_content
      end
    end
  end
end
