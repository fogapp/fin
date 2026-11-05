# typed: true

class Current < ActiveSupport::CurrentAttributes
  extend T::Sig

  attribute :user, :household, :api_token

  # Raised when code that structurally requires a household runs without one.
  class NoHousehold < StandardError; end

  # Typed accessor for the many callers that cannot proceed without a
  # household. `attribute` generates untyped readers, so `T.must(Current.
  # household)` reads as redundant to Sorbet under `typed: strict` and gets
  # stripped — taking the runtime guard with it. This keeps the assertion,
  # gives it a named error instead of a bare TypeError, and types the result.
  sig { returns(Household) }
  def self.household!
    household || raise(NoHousehold, "Current.household is not set")
  end
  # Observability: threads one causal episode (request or job graph) through
  # activity entries, workflow runs, and notifications. Set per request in
  # BaseController; propagated across enqueues by ApplicationJob.
  attribute :trace_id
  # Request-scoped memo for CashTransaction.spend_like — the cashflow
  # endpoint evaluates that scope a dozen+ times per request and each
  # evaluation used to re-run the excluded-merchants query.
  attribute :excluded_merchant_ids
  # DataVersion bump coalescing (see BumpsHouseholdDataVersion):
  # data_version_bumped_ids records which households already bumped in this
  # request/job; data_version_pending_ids records households whose repeat
  # bumps were suppressed and therefore need one final bump when the unit of
  # work finishes.
  attribute :data_version_bumped_ids, :data_version_pending_ids

  # The executor resets Current at the end of every request and job — flush
  # the coalesced bumps just before the pending set is wiped, so suppressed
  # writes are still guaranteed to rotate the cache version by the time the
  # unit of work completes.
  before_reset { Households::DataVersion.flush_pending_bumps! }
end
