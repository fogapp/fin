# typed: strict

module Api
  module Render
    class PlaidItem < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        items = ::PlaidItem.includes(:plaid_accounts).order(:institution_name).to_a
        # Only the accounts these items link to — not a grouped count over
        # every cash transaction in the household.
        linked_ids = items.flat_map { |item| item.plaid_accounts.filter_map(&:account_id) }.uniq
        counts = ::CashTransaction
          .where(account_id: linked_ids)
          .group(:account_id, :source)
          .count

        items.map { |item| serialize(item, counts) }
      end

      sig { params(item: ::PlaidItem, counts: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(item, counts = {})
        {
          id:               item.id,
          institution_name: item.institution_name,
          institution_id:   item.institution_id,
          status:           item.status,
          last_synced_at:   item.last_synced_at,
          plaid_accounts:   item.plaid_accounts.map { |a| serialize_account(a, counts) }
        }
      end

      private

      sig { params(account: ::PlaidAccount, counts: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_account(account, counts)
        {
          id:               account.id,
          name:             account.name,
          display_name:     account.display_name,
          mask:             account.mask,
          account_type:     account.account_type,
          account_subtype:  account.account_subtype,
          linked:           account.linked?,
          account_id:       account.account_id,
          bank_count:       counts[[ account.account_id, "bank" ]] || 0,
          credit_card_count: counts[[ account.account_id, "credit_card" ]] || 0
        }
      end
    end
  end
end
