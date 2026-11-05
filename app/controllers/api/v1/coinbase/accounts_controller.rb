# typed: true

module Api
  module V1
    module Coinbase
      class AccountsController < BaseController
        renders_with Api::Render::CoinbaseAccount

        def index
          config = CoinbaseConfiguration.current
          unless config.configured?
            return render json: { error: "Coinbase credentials not configured" }, status: :unprocessable_content
          end

          # The upstream call is an external HTTP round-trip per page view; a
          # short TTL absorbs repeat loads. Only the raw remote payload is
          # cached — the local balance_usd merge below stays live so a sync
          # that lands within the TTL still shows fresh USD values.
          raw = Rails.cache.fetch([ "coinbase_accounts", Current.household.id ], expires_in: 5.minutes) do
            CoinbaseClient.new.accounts
          end
          broker = Broker.find_by(name: "Coinbase")
          local_by_number = broker ? Account.where(broker: broker).index_by(&:account_number) : {}

          accounts = raw.map { |a| renderer.serialize(a, local_by_number[a["id"]]) }
          render json: accounts
        end
      end
    end
  end
end
