# typed: strict

# The single write API for the activity timeline. One row per meaningful
# operation — an index over the rich domain records, never a copy of them.
#
#   Activity.record(source: "plaid_sync", event: "sync.completed",
#                   summary: "Plaid sync: 12 added", subject: item,
#                   payload: { added: 12 }, duration_ms: 4200)
#
# Recording must never break the operation being observed: failures are
# logged and swallowed. The current trace id is attached automatically.
module Activity
  extend T::Sig

  sig do
    params(source: String, event: String, summary: String,
           severity: Severity, subject: T.untyped, payload: T::Hash[T.untyped, T.untyped],
           duration_ms: T.nilable(Numeric), caused_by: T.untyped,
           household_id: T.untyped, exception: T.nilable(Exception)).returns(T.nilable(ActivityEntry))
  end
  def self.record(source:, event:, summary:, severity: Severity::Info, subject: nil,
                  payload: {}, duration_ms: nil, caused_by: nil, household_id: nil, exception: nil)
    # The Fog error-tracker bridge: a rescued exception recorded here is
    # still a bug someone should see, so hand it to Rails.error (Flare
    # subscribes; handled: true marks it as rescued). Before the household
    # guard on purpose — error reporting must not depend on having a
    # household to file the timeline row under.
    report_exception(exception, source: source, event: event, severity: severity) if exception
    # Every sync, workflow and backup outcome passes through here, so one
    # counter charts them all in Glass. source and event are closed
    # vocabularies (a few dozen each); never a household or user id.
    Glass.increment("activity.recorded", tags: { source: source, event: event, severity: severity.serialize })
    household_id ||= Current.household&.id || subject.try(:household_id)
    return nil if household_id.nil?

    entry = ActivityEntry.create!(
      household_id: household_id,
      occurred_at:  Time.current,
      source:       source,
      event:        event,
      severity:     severity,
      summary:      summary.to_s.truncate(500),
      payload:      payload,
      subject:      subject,
      caused_by:    caused_by,
      trace_id:     Current.trace_id,
      duration_ms:  duration_ms&.round
    )
    publish_error_event(entry)
    entry
  rescue => e
    Rails.logger.error("[Activity] failed to record #{source}/#{event}: #{e.class}: #{e.message}")
    nil
  end

  # Error-severity entries become workflow triggers (system.error_recorded)
  # so users can build their own alerting — except workflow-sourced errors,
  # which already have workflow.run_failed and must not loop.
  sig { params(exception: Exception, source: String, event: String, severity: Severity).void }
  def self.report_exception(exception, source:, event:, severity:)
    rails_severity = severity.at_least?(Severity::Error) ? :error : :warning
    Rails.error.report(exception, handled: true, severity: rails_severity, source: "activity",
                       context: { source: source, event: event })
  rescue StandardError => e
    Rails.logger.error("[Activity] error report failed: #{e.class}: #{e.message}")
  end
  private_class_method :report_exception

  sig { params(entry: ActivityEntry).void }
  def self.publish_error_event(entry)
    # at_least? also catches "critical", which the shared Severity
    # vocabulary now permits on activity entries.
    return unless entry.severity.is_a?(Severity) && entry.severity.at_least?(Severity::Error)
    return if entry.source == "workflow"

    Workflows::Events.publish("system.error_recorded", subject: entry,
                              payload: { "source" => entry.source, "event" => entry.event })
  end
  private_class_method :publish_error_event
end
