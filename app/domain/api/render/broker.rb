# typed: strict

module Api
  module Render
    class Broker < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        ::Broker.includes(:accounts).order(:name).map { |b| serialize(b) }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        broker = ::Broker.includes(:accounts).find(params[:id])
        serialize(broker).merge(
          accounts: broker.accounts.sort_by { |a| a.name.to_s }.map { |a| serialize_account(a) }
        )
      end

      sig { params(broker: ::Broker).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(broker)
        {
          id:            broker.id,
          name:          broker.name,
          account_count: broker.accounts.length
        }
      end

      private

      sig { params(account: ::Account).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_account(account)
        {
          id:             account.id,
          name:           account.name,
          account_number: account.account_number,
          account_type:   account.account_type
        }
      end
    end
  end
end
