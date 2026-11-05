# typed: true

module Reconciliation
  # Nightly ledger-vs-custodian reconciliation for every household, plus a
  # position rebuild first so the ledger side is current.
  class SweepJob < ApplicationJob
    extend T::Sig

    queue_as :default
    limits_concurrency to: 1, key: -> { "reconciliation_sweep" }

    sig { void }
    def perform
      each_household do |household|
        Positions::Rebuild.all(household: household)
        findings = Reconciliation::Engine.run(household)
        Rails.logger.info("[Reconciliation::SweepJob] household=#{household.id} findings=#{findings.size}")
      end
    end
  end
end
