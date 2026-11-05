# typed: true

module Api
  module V1
    class TransfersController < BaseController
      renders_with Api::Render::Transfer

      def index
        scope = Transfer.order(created_at: :desc)
        if params.key?(:confirmed)
          confirmed = ActiveModel::Type::Boolean.new.cast(params[:confirmed])
          scope = confirmed ? scope.confirmed : scope.candidates unless confirmed.nil?
        end
        render json: renderer.serialize_all_with_details(scope.limit(200))
      end

      def for_transaction
        tx_id   = params.require(:transaction_id)
        tx_type = params.require(:transaction_type)
        # Confirmed transfers too — the drawer shows kind/treatment for linked
        # rows, not just the pending-candidate confirm card.
        t = Transfer.find_by(from_transaction_id: tx_id, from_transaction_type: tx_type) ||
            Transfer.find_by(to_transaction_id:   tx_id, to_transaction_type:   tx_type)
        return render json: nil unless t
        render json: renderer.serialize_with_transaction_details(t)
      end

      def candidates
        # Candidates are pre-computed by DetectTransferCandidatesJob and stored
        # as unconfirmed Transfer records — no live SQL joins needed.
        transfers = Transfer.candidates.order(created_at: :desc).limit(200)
        render json: renderer.serialize_all_with_details(transfers)
      end

      def scan
        DetectTransferCandidatesJob.perform_later
        render_queued
      end

      def create
        t = Transfers::ManualLink.call(transfer_params.to_h, auto_confirm: ActiveModel::Type::Boolean.new.cast(params[:auto_confirm]) == true)
        render json: renderer.serialize(t), status: :created
      end

      def confirm
        t = Transfer.find(params[:id])
        t.confirm!
        render json: renderer.serialize(t)
      end

      def dismiss
        Transfers::Dismiss.call(Transfer.find(params[:id]))
        head :no_content
      rescue Transfers::Dismiss::ConfirmedTransfer => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # Treatment/annotation edits only (include_in_spend toggle, kind
      # correction, note) — the linked sides are immutable; relink by
      # destroying and recreating.
      def update
        t = Transfer.find(params[:id])
        attrs = params.permit(:include_in_spend, :note)
        # Validate up front so a bad kind 422s listing the allowed values
        # instead of surfacing as an opaque inclusion-validation failure.
        attrs[:kind] = enum_param(Transfer::Kind, :kind) if params[:kind].present?
        t.update!(attrs)
        render json: renderer.serialize(t)
      end

      def destroy
        Transfer.find(params[:id]).destroy! # model unlinks both sides
        head :no_content
      end

      private

      def transfer_params
        params.permit(:from_transaction_id, :from_transaction_type,
                      :to_transaction_id,   :to_transaction_type,
                      :counterparty_account_id,
                      :amount, :note, :kind, :include_in_spend)
      end
    end
  end
end
