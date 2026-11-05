# typed: true

module Api
  module V1
    module Plaid
      class AccountsController < BaseController
        renders_with Api::Render::PlaidAccount

        def index
          render json: renderer.index
        end

        def update
          plaid_account = ::PlaidAccount.find(params[:id])
          was_linked    = plaid_account.linked?
          plaid_account.update!(account_id: params[:account_id].presence)

          if !was_linked && plaid_account.linked?
            T.must(plaid_account.plaid_item).update!(cursor: nil)
          end

          render json: renderer.serialize(plaid_account.reload)
        end

        def sync
          plaid_account = ::PlaidAccount.find(params[:id])
          PlaidSyncJob.perform_later(plaid_account.plaid_item_id, plaid_account.id)
          render_queued(plaid_account_id: plaid_account.id)
        end
      end
    end
  end
end
