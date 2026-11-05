# typed: true

module Api
  module V1
    class ReconciliationController < BaseController
      # Accept the custodian balance for one drift finding (issue key
      # "reconciliation:<account_id>:<security_id>").
      def accept
        _, account_id, security_id = params[:key].to_s.split(":")
        account = Account.find(account_id)
        security = Security.find(security_id)

        result = Reconciliation::AcceptBalance.call(account: account, security: security)
        render json: { status: result.status, delta: result.delta.to_f }
      end

      def accept_all
        Reconciliation::AcceptAllJob.perform_later(Current.household.id.to_s)
        render_queued
      end
    end
  end
end
