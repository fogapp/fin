# typed: strict

module Api
  module Render
    class AlchemyWallet < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        ::AlchemyWallet.includes(:account, :alchemy_wallet_syncs).order(:created_at).map { |w| serialize(w) }
      end

      sig { params(wallet: ::AlchemyWallet).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(wallet)
        account = wallet.account
        {
          id:             wallet.id,
          address:        wallet.address,
          name:           wallet.name,
          display_name:   wallet.display_name,
          networks:       wallet.networks,
          active:         wallet.active,
          last_synced_at: wallet.last_synced_at,
          last_error:     wallet.last_error,
          account:        account && {
            id:      account.id,
            name:    account.name,
            balance: account.balance&.to_f
          },
          syncs: wallet.alchemy_wallet_syncs
            .select { |s| wallet.networks.include?(s.network) }
            .sort_by(&:network)
            .map do |s|
              {
                network:                 s.network,
                last_synced_at:          s.last_synced_at,
                backfill_status:         s.backfill_status.to_s,
                backfill_transfer_count: s.backfill_transfer_count,
                last_error:              s.last_error
              }
            end
        }
      end
    end
  end
end
