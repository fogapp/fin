# typed: true

module Api
  module V1
    module Alchemy
      class SyncController < BaseController
        def create
          unless AlchemyConfiguration.current.configured?
            return render json: { error: "Alchemy not configured" }, status: :unprocessable_content
          end
          AlchemySyncJob.perform_later(Current.household.id)
          render_queued
        end
      end
    end
  end
end
