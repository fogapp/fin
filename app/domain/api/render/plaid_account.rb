# typed: strict

module Api
  module Render
    class PlaidAccount < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        ::PlaidAccount.includes(:plaid_item, :account).order(:name).map { |a| serialize(a) }
      end

      sig { params(account: ::PlaidAccount).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(account)
        {
          id:               account.id,
          name:             account.name,
          display_name:     account.display_name,
          mask:             account.mask,
          account_type:     account.account_type,
          account_subtype:  account.account_subtype,
          linked:           account.linked?,
          account_id:       account.account_id,
          plaid_item_id:    account.plaid_item_id,
          institution_name: T.must(account.plaid_item).institution_name,
          balance_current:    account.balance_current&.to_f,
          balance_available:  account.balance_available&.to_f,
          balance_limit:      account.balance_limit&.to_f,
          balance_currency:   account.balance_currency,
          balance_updated_at: account.balance_updated_at&.iso8601
        }
      end
    end
  end
end
