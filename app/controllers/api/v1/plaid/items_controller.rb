# typed: true

module Api
  module V1
    module Plaid
      class ItemsController < BaseController
        renders_with Api::Render::PlaidItem

        include PlaidErrorHandling

        def index
          render json: renderer.index
        end

        def create
          public_token = params.require(:public_token)
          client       = PlaidClient.new

          exchange  = client.exchange_public_token(public_token)
          item_resp = client.get_item(exchange.access_token)
          inst_resp = client.get_institution(item_resp.item.institution_id)
          accts     = client.get_accounts(exchange.access_token).accounts

          # All-or-nothing: a mid-loop failure would otherwise leave a
          # half-linked item that can't be retried (item_id is unique). The
          # Plaid token exchange above stays outside the transaction.
          plaid_item = ActiveRecord::Base.transaction do
            item = ::PlaidItem.create!(
              item_id:          exchange.item_id,
              access_token:     exchange.access_token,
              institution_id:   item_resp.item.institution_id,
              institution_name: inst_resp.institution.name
            )

            accts.each do |acct|
              pa = item.plaid_accounts.create!(
                plaid_account_id: acct.account_id,
                name:             acct.name,
                mask:             acct.mask,
                account_type:     acct.type,
                account_subtype:  acct.subtype
              )
              pa.link_to_new_account!
            end

            item
          end

          PlaidSyncJob.perform_later(plaid_item.id)
          render json: renderer.serialize(plaid_item.reload), status: :created
        rescue => e
          render_plaid_error(e, fallback: "Failed to link Plaid item")
        end

        def destroy
          ::PlaidItem.find(params[:id]).destroy!
          head :no_content
        end

        def sync
          item = ::PlaidItem.find(params[:id])
          PlaidSyncJob.perform_later(item.id)
          render_queued(item_id: item.id)
        end
      end
    end
  end
end
