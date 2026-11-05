# typed: true

module Reconciliation
  # Bulk remediation: accept the custodian balance for every open drift
  # finding in the household. One summary activity entry.
  class AcceptAllJob < ApplicationJob
    extend T::Sig

    queue_as :default
    limits_concurrency to: 1, key: ->(household_id) { "reconcile_accept_#{household_id}" }

    sig { params(household_id: String).void }
    def perform(household_id)
      household = Household.find_by(id: household_id)
      return unless household

      Current.set(household: household) do
        adjusted = T.let(0, Integer)
        skipped = T.let(0, Integer)
        Issue.active.where("key LIKE 'reconciliation:%'").find_each do |issue|
          _, account_id, security_id = issue.key.to_s.split(":")
          account = Account.find_by(id: account_id)
          security = Security.find_by(id: security_id)
          next skipped += 1 unless account && security

          result = Reconciliation::AcceptBalance.call(account: account, security: security)
          result.status == :adjusted ? adjusted += 1 : skipped += 1
        end

        Activity.record(
          source: "reconciliation", event: "balances_accepted",
          summary: "Accepted custodian balances: #{adjusted} adjustment#{adjusted == 1 ? '' : 's'} written" \
                   "#{skipped.positive? ? ", #{skipped} already in sync" : ''}",
          payload: { adjusted: adjusted, skipped: skipped },
          household_id: household.id
        )
      end
    end
  end
end
