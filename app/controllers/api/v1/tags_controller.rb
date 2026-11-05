# typed: true

module Api
  module V1
    class TagsController < BaseController
      renders_with Api::Render::Tag

      def index
        render json: renderer.index
      end

      def show
        render json: renderer.show
      end

      def create
        tag = Tag.new(name: params[:name].to_s.strip)
        tag.save!
        render json: renderer.serialize(tag), status: :created
      end

      def destroy
        Tag.find(params[:id]).destroy!
        head :no_content
      end
    end
  end
end
