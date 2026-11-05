# typed: true

module Api
  module V1
    module Coinbase
      class SyncController < BaseController
        def create
          unless ::Coinbase.configured?
            return render json: { error: "Coinbase not configured" }, status: :unprocessable_content
          end
          CoinbaseSyncJob.perform_later(Current.household.id)
          render_queued
        end
      end
    end
  end
end
