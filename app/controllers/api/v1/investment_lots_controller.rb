# typed: true

module Api
  module V1
    class InvestmentLotsController < BaseController
      renders_with Api::Render::InvestmentLot

      def index
        render json: renderer.index
      end

      def generate
        security_id = params.require(:security_id)
        service = InvestmentLots::GenerateFromTransactions.new(security_id: security_id)

        if params[:commit]
          replace = ActiveModel::Type::Boolean.new.cast(params[:replace]) || false
          unless replace
            existing_count = InvestmentLot.where(security_id: security_id).count
            if existing_count > 0
              return render json: { error: "lots_exist", count: existing_count }, status: :conflict
            end
          end
          lots = service.commit!(replace: replace)
          render json: lots.map { |l| renderer.serialize(l) }, status: :created
        else
          render json: service.preview
        end
      end

      def create
        lot = InvestmentLot.new(lot_params)
        lot.save!
        render json: renderer.serialize(lot), status: :created
      end

      def update
        lot = InvestmentLot.find(params[:id])
        lot.update!(lot_params)
        render json: renderer.serialize(lot)
      end

      def destroy
        InvestmentLot.find(params[:id]).destroy!
        head :no_content
      end

      private

      def lot_params
        params.permit(:security_id, :acquired_date, :quantity, :cost_basis, :notes)
              .merge(account_reference)
      end
    end
  end
end
