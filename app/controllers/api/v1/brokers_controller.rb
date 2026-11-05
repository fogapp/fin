# typed: true

module Api
  module V1
    class BrokersController < BaseController
      renders_with Api::Render::Broker

      def index
        render json: renderer.index
      end

      def show
        render json: renderer.show
      end

      def create
        broker = Broker.new(name: params[:name].to_s.strip)
        broker.save!
        render json: renderer.serialize(broker), status: :created
      end

      def update
        broker = Broker.find(params[:id])
        broker.update!(name: params[:name].to_s.strip)
        render json: renderer.serialize(broker)
      end

      def destroy
        broker = Broker.find(params[:id])
        broker.destroy!
        head :no_content
      rescue ActiveRecord::RecordNotDestroyed
        render json: { error: "Cannot delete a broker that still has accounts." }, status: :unprocessable_content
      end
    end
  end
end
