# typed: strict

module Api
  module Render
    class CoinbaseAccount < Api::Render::Base
      extend T::Sig

      # `a` is the raw Coinbase API account hash; `local` is the matching
      # local Account (if synced), whose balance_usd stays live even while
      # the remote payload is served from cache.
      sig { params(a: T::Hash[String, T.untyped], local: T.nilable(::Account)).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(a, local = nil)
        {
          id:          a["id"],
          name:        a["name"],
          currency:    a.dig("balance", "currency"),
          balance:     a.dig("balance", "amount"),
          type:        a["type"],
          balance_usd: local&.balance_usd&.to_f
        }
      end
    end
  end
end
