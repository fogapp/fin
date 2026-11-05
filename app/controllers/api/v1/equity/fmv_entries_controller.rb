# typed: true

module Api
  module V1
    module Equity
      class FmvEntriesController < BaseController
        renders_with Api::Render::Equity

        def create
          company = EquityCompany.find(params[:company_id])
          entry = company.fmv_entries.create!(entry_params)
          render json: renderer.fmv_entry(entry), status: :created
        end

        def destroy
          EquityFmvEntry.find(params[:id]).destroy!
          head :no_content
        end

        private

        def entry_params
          params.permit(:price_per_share, :effective_date, :source)
        end
      end
    end
  end
end
