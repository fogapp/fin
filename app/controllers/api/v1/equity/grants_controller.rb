# typed: true

module Api
  module V1
    module Equity
      class GrantsController < BaseController
        renders_with Api::Render::Equity

        def create
          company = EquityCompany.find(params.require(:equity_company_id))
          grant = company.grants.create!(grant_params)
          render json: renderer.grant(grant), status: :created
        end

        def update
          grant = EquityGrant.find(params[:id])
          grant.update!(grant_params)
          render json: renderer.grant(grant.reload)
        end

        def destroy
          EquityGrant.find(params[:id]).destroy!
          head :no_content
        end

        private

        def grant_params
          permitted = params.permit(
            :label, :grant_type, :grant_date, :vesting_commencement_date,
            :quantity, :strike_price, :early_exercisable, :double_trigger,
            :expiration_date, :pte_window_days, :vesting_interval,
            :vesting_occurrences, :cliff_installments, :notes,
            custom_tranches: [ :date, :quantity ]
          )
          # An explicit empty array clears a custom schedule; absent leaves it.
          permitted[:custom_tranches] = [] if params[:custom_tranches] == []
          permitted
        end
      end
    end
  end
end
