# typed: strict

# The coordinator for one Plaid item sync. Owns the Result shape, cursor
# persistence, item status, event publishing, and the Activity roll-up;
# each data domain is delegated to its service under Plaid::* —
# TransactionSync (cursor-paged cash transactions), BalanceSync,
# HoldingSync, and InvestmentTransactionSync — all sharing one
# Plaid::SyncContext.
class PlaidSyncer
  extend T::Sig

  # errors: transaction-page processing failures — these hold the cursor back.
  # sub_errors: balance/holdings/investment-txn failures — surfaced in the
  # recorded activity but never allowed to block the transactions cursor.
  Result = Struct.new(:added, :modified, :removed, :errors, :sub_errors, keyword_init: true)

  sig { params(plaid_item: PlaidItem, only_account: T.nilable(PlaidAccount)).void }
  def initialize(plaid_item, only_account: nil)
    @plaid_item   = T.let(plaid_item, PlaidItem)
    @only_account = T.let(only_account, T.nilable(PlaidAccount))
    @client       = T.let(PlaidClient.new, T.untyped)
    # True when the item had no cursor at sync start (first sync after a
    # link or reconnect) — gates the content-based dedup adoption path.
    @first_sync   = T.let(false, T::Boolean)
  end

  sig { returns(PlaidSyncer::Result) }
  def call
    sync_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Result.new(added: 0, modified: 0, removed: 0, errors: [], sub_errors: [])
    cursor      = T.let(@plaid_item.cursor, T.nilable(String))
    @first_sync = cursor.nil?
    context = Plaid::SyncContext.new(plaid_item: @plaid_item, client: @client,
                                     only_account: @only_account, first_sync: @first_sync)
    # Constructed up front: its date window derives from last_synced_at,
    # which this coordinator stamps to Time.current further down.
    investment_sync = Plaid::InvestmentTransactionSync.new(context)

    Plaid::TransactionSync.new(context).call(result, cursor: cursor) { |c| persist_cursor(c, result) }

    if @only_account.nil?
      @plaid_item.update!(last_synced_at: Time.current, status: "active", error_message: nil)
    end

    Plaid::BalanceSync.new(context).call(result)
    Plaid::HoldingSync.new(context).call(result)
    investment_sync.call(result)
    Recurring::DetectJob.perform_later if result.added > 0 || result.modified > 0
    Workflows::Events.publish("plaid.sync_completed", subject: @plaid_item,
                              payload: { "added" => result.added, "modified" => result.modified,
                                         "removed" => result.removed, "errors" => result.errors.size })
    skipped = investment_sync.skipped_types
    if skipped.any?
      Activity.record(
        source: "plaid_sync", event: "sync.transactions_skipped", severity: Severity::Warning,
        summary: "Plaid sync skipped #{skipped.values.sum} unmapped investment transaction(s): " \
                 "#{skipped.map { |k, v| "#{k}×#{v}" }.join(', ')}",
        subject: @plaid_item, payload: { skipped_types: skipped },
        household_id: @plaid_item.household_id
      )
    end
    # Transaction-page failures held the cursor back and need attention now
    # (severity "error"); sub-sync failures (balances/holdings/investment
    # txns) are self-healing on the next run (severity "warning").
    severity = if result.errors.any?
      Severity::Error
    elsif result.sub_errors.any?
      Severity::Warning
    else
      Severity::Info
    end
    Activity.record(
      source: "plaid_sync", event: "sync.completed",
      severity: severity,
      summary: "Plaid sync #{@plaid_item.institution_name.presence || @plaid_item.item_id}: " \
               "#{result.added} added, #{result.modified} modified, #{result.removed} removed" \
               "#{result.errors.any? ? ", #{result.errors.size} errors" : ''}" \
               "#{result.sub_errors.any? ? ", #{result.sub_errors.size} sub-sync errors" : ''}",
      subject: @plaid_item,
      payload: { added: result.added, modified: result.modified,
                 removed: result.removed, errors: result.errors.size,
                 sub_errors: result.sub_errors.size },
      duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - sync_started) * 1000
    )
    result
  rescue Plaid::ApiError => e
    msg = Plaid::ErrorInfo.from(e).message || e.message
    @plaid_item.update!(status: "error", error_message: msg)
    record_sync_failure(msg, sync_started.to_f)
    raise
  rescue => e
    @plaid_item.update!(status: "error", error_message: e.message)
    record_sync_failure(e.message, sync_started.to_f)
    raise
  end

  private

  # Persist the cursor after each cleanly-applied page so a later failure
  # can't discard progress, with two guards:
  #
  #   - Never for a single-account sync — a full sync later still needs to
  #     see transactions for the other accounts.
  #   - Not while the very first sync has produced no data: Plaid processes
  #     historical transactions asynchronously after a new item is connected
  #     and can take several minutes. Keeping cursor nil means the next sync
  #     starts from the beginning and picks up the backfill once it's ready.
  sig { params(cursor: T.nilable(String), result: PlaidSyncer::Result).void }
  def persist_cursor(cursor, result)
    return if @only_account
    return if @first_sync && result.added.zero? && result.modified.zero?

    @plaid_item.update!(cursor: cursor)
  end

  sig { params(message: T.untyped, sync_started: Float).void }
  def record_sync_failure(message, sync_started)
    Activity.record(
      source: "plaid_sync", event: "sync.failed", severity: Severity::Error,
      summary: "Plaid sync #{@plaid_item.institution_name.presence || @plaid_item.item_id} failed: #{message}",
      subject: @plaid_item,
      duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - sync_started) * 1000,
      household_id: @plaid_item.household_id
    )
  end
end
