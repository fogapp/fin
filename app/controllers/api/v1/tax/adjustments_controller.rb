# typed: true

module Api
  module V1
    module Tax
      # Arbitrary per-year tax line items (K-1s, rental income, property
      # tax, credits, off-ledger contributions) — the escape hatch that
      # keeps unusual years representable. Reads come through the year
      # report, folded into each section by kind.
      class AdjustmentsController < BaseController
        renders_with Api::Render::Tax

        def create
          adjustment = TaxAdjustment.new(adjustment_params)
          adjustment.save!
          render json: renderer.adjustment(adjustment), status: :created
        end

        def update
          adjustment = TaxAdjustment.find(params[:id])
          adjustment.update!(adjustment_params)
          render json: renderer.adjustment(adjustment)
        end

        def destroy
          TaxAdjustment.find(params[:id]).destroy!
          head :no_content
        end

        private

        def adjustment_params
          params.permit(:tax_year, :kind, :jurisdiction, :label, :amount, :bucket, :notes)
        end
      end
    end
  end
end
