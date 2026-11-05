# typed: true

class PlaidSyncJob < ApplicationJob
  extend T::Sig

  queue_as :default
  # Overlapping syncs race on the item cursor and the content-dedup path.
  # The no-arg form only fans out per-item jobs (it never syncs inline), so
  # every job that actually executes a sync carries a real per-item key.
  limits_concurrency to: 1, key: ->(plaid_item_id = nil, _account = nil) { plaid_item_id || "all" }

  # Transient Plaid failures (rate limits, institution downtime, 5xx) retry
  # with backoff. Errors that need user action (re-login, revoked consent)
  # can't succeed on retry — PlaidSyncer already marks the item status
  # "error" with the message before re-raising, so those are discarded in
  # perform's rescue below and never reach this handler.
  retry_on ::Plaid::ApiError, wait: :polynomially_longer, attempts: 5

  NOT_CONFIGURED_ISSUE_KEY = "plaid_not_configured"

  sig { params(plaid_item_id: T.nilable(String), plaid_account_id: T.nilable(String)).void }
  def perform(plaid_item_id = nil, plaid_account_id = nil)
    return fan_out if plaid_item_id.nil?

    item = PlaidItem.find_by(id: plaid_item_id)
    return unless item

    Current.set(household: item.household) do
      only_account = plaid_account_id ? item.plaid_accounts.find_by(id: plaid_account_id) : nil
      result = PlaidSyncer.new(item, only_account: only_account).call
      Issue.resolve!(NOT_CONFIGURED_ISSUE_KEY)
      label  = only_account ? "account=#{only_account.plaid_account_id}" : "item=#{item.item_id}"
      Rails.logger.info("[PlaidSyncJob] #{label} added=#{result.added} modified=#{result.modified} removed=#{result.removed} errors=#{result.errors.size}")
    rescue PlaidClient::NotConfigured => e
      # Retrying can't conjure credentials; say what's missing and skip.
      Issue.raise_once!(key: NOT_CONFIGURED_ISSUE_KEY, title: "Plaid sync is off: no credentials",
                        body: e.message, severity: Severity::Error, source: "plaid")
      Rails.logger.warn("[PlaidSyncJob] item=#{item.item_id} skipped: #{e.message}")
    end
  rescue ::Plaid::ApiError => e
    # Errors that need the user to re-link or re-consent aren't retried.
    raise if ::Plaid::ErrorInfo.from(e).retriable?

    # Needs user action to fix (re-login / consent). PlaidSyncer has already
    # marked the item status "error" with the message and recorded a
    # sync.failed activity — retrying would just burn Plaid quota.
    Rails.logger.error("[PlaidSyncJob] item=#{plaid_item_id} non-retriable Plaid error: #{e.message}")
  end

  private

  # Every active item gets its own job so limits_concurrency serializes it
  # against user-triggered per-item syncs on the same key.
  sig { void }
  def fan_out
    PlaidItem.active.find_each { |item| self.class.perform_later(item.id) }
  end
end
