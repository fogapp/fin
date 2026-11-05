# typed: true

module Api
  module V1
    class MerchantsController < BaseController
      renders_with Api::Render::Merchant

      def index
        render json: renderer.index
      end

      def show
        render json: renderer.show
      end

      def create
        merchant = Merchant.find_or_initialize_by(name: merchant_params[:name])
        merchant.assign_attributes(merchant_params.except(:name))
        created = merchant.new_record?
        merchant.save!
        render json: renderer.serialize(merchant), status: (created ? :created : :ok)
      end

      def update
        merchant = Merchant.find(params[:id])
        merchant.update!(merchant_params)
        render json: renderer.serialize(merchant)
      end

      def destroy
        Merchant.find(params[:id]).destroy!
        head :no_content
      end

      def exclude
        Merchant.find(params[:id]).update!(excluded: true)
        head :no_content
      end

      def include
        Merchant.find(params[:id]).update!(excluded: false)
        head :no_content
      end

      private

      def merchant_params
        params.permit(:name, :category_id, :notes)
      end
    end
  end
end
