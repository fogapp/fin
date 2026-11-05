# typed: true

module Api
  module V1
    class CashTransactionsController < BaseController
      renders_with Api::Render::CashTransaction

      def index
        render json: renderer.index
      end

      def show
        render json: renderer.show
      end

      def create
        t = CashTransaction.new(transaction_params)
        t.save!
        render json: renderer.serialize(t), status: :created
      end

      def update
        t = CashTransaction.find(params[:id])
        t.update!(transaction_params)
        render json: renderer.serialize(t)
      end

      def destroy
        CashTransaction.find(params[:id]).destroy!
        head :no_content
      end

      def filter
        render json: renderer.filter
      end

      def add_tag
        t = CashTransaction.find(params[:id])
        tag = Tag.find(params[:tag_id])
        t.tags << tag unless t.tags.include?(tag)
        render json: renderer.serialize(t.reload)
      end

      def remove_tag
        t = CashTransaction.find(params[:id])
        t.tags.delete(Tag.find(params[:tag_id]))
        render json: renderer.serialize(t.reload)
      end

      # Other transactions with the same (or a very similar) description.
      def similar
        render json: renderer.similar
      end

      # Everything the transaction page explains a row with: its history,
      # cadence, subscription, budget impact, duplicates and same-day activity.
      def context
        render json: renderer.context
      end

      # Returns transactions near the given transaction for manual transfer pairing.
      def transfer_search
        render json: renderer.transfer_search
      end

      def bulk_update
        ids = Array(params[:ids]).map(&:to_s).select(&:present?)
        raise ActionController::BadRequest, "ids is required" if ids.empty?

        result = CashTransactions::BulkUpdater.new(
          ids:         ids,
          account_id:  params[:account_id],
          merchant_id: params[:merchant_id],
          category_id: params[:category_id],
          tag_ids:     params[:tag_ids]
        ).call

        render json: result
      end

      private

      def transaction_params
        # transaction_type deliberately stays a raw string (no enum_param):
        # the column is OPEN — CSV importers pass bank "Type" values through
        # verbatim. See the CashTransaction::TransactionType comment.
        params.permit(:source, :transaction_date, :post_date, :description, :amount,
                      :transaction_type, :category_id, :merchant_id,
                      :balance, :memo, :source_row_hash, :loan_id, :budget_excluded)
              .merge(account_reference)
      end
    end
  end
end
