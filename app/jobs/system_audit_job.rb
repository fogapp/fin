# typed: true

# The per-household audit sweep: each domain's checks live in its service
# under Audits::*; this job only iterates households, runs them in order,
# and records the completion activity.
class SystemAuditJob < ApplicationJob
  queue_as :default

  AUDITS = [
    Audits::Plaid,
    Audits::InstrumentIdentity,
    Audits::DuplicateHoldings,
    Audits::SecurityConversions,
    Audits::InvestmentTransactions,
    Audits::Imports,
    Audits::FailedJobs
  ].freeze

  def perform
    each_household do
      AUDITS.each { |audit| audit.new.call }
      open_issues = Issue.active.count
      Activity.record(
        source: "system_audit", event: "audit.completed",
        summary: "System audit completed (#{open_issues} open issue#{open_issues == 1 ? '' : 's'})",
        payload: { open_issues: open_issues }
      )
    end
  end
end
