# typed: true

module Api
  module V1
    class AccountsController < BaseController
      renders_with Api::Render::Account

      def index
        # Fetched by ~8 pages; grouped counts + position sums per request
        # added up. Balance writes bump DataVersion so staleness is bounded.
        render_cached("accounts") { renderer.index }
      end

      def show
        render json: renderer.show
      end

      def holdings
        render json: Api::Render::AccountHoldings.new(params: params).show
      end

      def create
        account = Account.new(account_params)
        account.save!
        render json: renderer.serialize(account), status: :created
      end

      def update
        account = Account.find(params[:id])
        old_balance = account.balance

        Account.transaction do
          account.update!(account_params)
          account.record_manual_balance_change!(old_balance) if params.key?(:balance)
        end

        render json: renderer.serialize(account)
      end

      private

      def account_params
        params.permit(:name, :account_number, :account_type, :balance, :balance_currency, :balance_usd, :broker_id, :hidden, :kind, :tax_treatment)
      end
    end
  end
end
