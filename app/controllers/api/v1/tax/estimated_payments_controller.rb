# typed: true

module Api
  module V1
    module Tax
      # Estimated-payment ledger writes; reads come through the year report
      # (payments section), so there is no index action.
      class EstimatedPaymentsController < BaseController
        renders_with Api::Render::Tax

        def create
          payment = EstimatedTaxPayment.new(payment_params)
          payment.save!
          render json: renderer.estimated_payment(payment), status: :created
        end

        def destroy
          EstimatedTaxPayment.find(params[:id]).destroy!
          head :no_content
        end

        private

        def payment_params
          params.permit(:tax_year, :jurisdiction, :paid_on, :amount, :notes)
        end
      end
    end
  end
end
