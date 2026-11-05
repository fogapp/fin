# typed: true

module Workflows
  # Periodic monitor evaluation for conditions that change without a record
  # event we observe (e.g. balances written via update_columns by syncers,
  # or time-dependent predicates like overdue?).
  class MonitorSweepJob < ApplicationJob
    extend T::Sig

    queue_as :workflows
    limits_concurrency to: 1, key: -> { "workflow_monitor_sweep" }

    sig { void }
    def perform
      each_household do
        Workflow.active.for_trigger(Catalog::MONITOR_TRIGGER).each do |workflow|
          # sweep! narrows the walk to matching rows via SQL when it can, and
          # batches state lookups either way.
          Monitor.new(workflow).sweep!
        end
      end
    end
  end
end
