# typed: true

module Api
  module V1
    class LoansController < BaseController
      renders_with Api::Render::Loan

      def index
        render json: renderer.index
      end

      def show
        render json: renderer.show
      end

      def create
        loan = Loan.new(loan_params)
        loan.save!
        render json: renderer.serialize(loan), status: :created
      end

      def update
        loan = Loan.find(params[:id])
        loan.update!(loan_params)
        render json: renderer.serialize(loan.reload)
      end

      def destroy
        Loan.find(params[:id]).destroy!
        head :no_content
      end

      # GET /loans/:id/candidate_transactions
      # Returns cash transactions from the linked account that could be payments
      def candidate_transactions
        render json: renderer.candidate_transactions
      end

      private

      def loan_params
        params.permit(
          :name, :lender, :loan_type, :original_principal, :interest_rate,
          :term_months, :start_date, :monthly_payment, :status, :notes,
          :merchant_id, :balance_anchor_amount, :balance_anchor_date, :interest_only,
          :escrow_property_tax, :escrow_insurance, :escrow_other
        ).merge(account_reference)
      end
    end
  end
end
