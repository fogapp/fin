# typed: true

module Api
  module V1
    module Alchemy
      class WalletsController < BaseController
        renders_with Api::Render::AlchemyWallet

        def index
          render json: renderer.index
        end

        def create
          wallet = AlchemyWallet.create!(wallet_params)
          orchestrator.wallet_added(AlchemyConfiguration.current)
          render json: renderer.serialize(wallet), status: :created
        end

        def update
          wallet = AlchemyWallet.find(params[:id])
          wallet.update!(wallet_params)
          orchestrator.wallet_changed(AlchemyConfiguration.current)
          render json: renderer.serialize(wallet)
        end

        def destroy
          wallet = AlchemyWallet.find(params[:id])
          wallet.destroy!
          orchestrator.wallet_changed(AlchemyConfiguration.current)
          head :no_content
        end

        # Reset and re-run the on-chain history backfill for this wallet.
        def backfill
          wallet = AlchemyWallet.find(params[:id])
          config = AlchemyConfiguration.current
          unless config.transactions_configured?
            return render json: { error: "Transaction sync is not enabled" }, status: :unprocessable_content
          end

          wallet.alchemy_wallet_syncs.where(network: wallet.networks).find_each do |state|
            state.update!(backfill_status: AlchemyWalletSync::BackfillStatus::Pending,
                          backfill_cursor: {}, backfill_transfer_count: 0, last_error: nil)
          end
          wallet.networks.each { |network| ::Alchemy::BackfillJob.perform_later(wallet.id, network) }
          render_queued
        end

        private

        def orchestrator = ::Alchemy::Orchestrator.new(Current.household!.id)

        def wallet_params
          wallet = params.require(:alchemy_wallet)
          wallet.permit(:address, :name, :active, networks: []).merge(account_reference(wallet))
        end
      end
    end
  end
end
