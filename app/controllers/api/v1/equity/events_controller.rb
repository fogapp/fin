# typed: true

module Api
  module V1
    module Equity
      class EventsController < BaseController
        renders_with Api::Render::Equity

        def create
          grant = EquityGrant.find(params[:grant_id])
          event = grant.events.create!(event_params)
          render json: renderer.event(event), status: :created
        end

        def destroy
          EquityGrantEvent.find(params[:id]).destroy!
          head :no_content
        end

        private

        def event_params
          params.permit(
            :kind, :occurred_on, :quantity, :share_price, :method, :buyer_type,
            :election_83b, :election_83b_date, :shares_withheld, :notes
          )
        end
      end
    end
  end
end
