# typed: strict

# What Fin tells fog's event stream. Two doors in:
#
# - Every in-app Notification (a workflow's `notify`, a release announcement)
#   is published as `fin.notification`, after commit and from a job, so the
#   reader sees what the bell menu and the ntfy push already show — never
#   more. The ntfy push carries on unchanged beside it.
# - A workflow's `fog_event` action publishes a structured event typed by
#   what triggered it (`fin.budget.category_exceeded`), for a reader that
#   routes by type rather than by a person reading a title.
#
# Publishing is a notice, not a transaction: off fog nothing is sent, and a
# failure is recorded on the activity timeline without stopping anything.
module FogEvents
  extend T::Sig

  # fog's rule for `type` (and the bound on `id`).
  TYPE_PATTERN = T.let(/\A[a-z0-9][a-z0-9._-]{0,127}\z/, Regexp)
  MAX_ID_LENGTH = T.let(128, Integer)

  class Outcome < T::Enum
    enums do
      Published = new("published")
      Unavailable = new("unavailable")
      Failed = new("failed")
    end
  end

  sig { returns(T::Boolean) }
  def self.available?
    ENV["FOG_API_URL"].present? && ENV["FOG_API_TOKEN"].present?
  end

  sig { params(notification: Notification).returns(Outcome) }
  def self.notification(notification)
    run = notification.workflow_run
    publish(
      type: "fin.notification", id: "notification-#{notification.id}",
      subject: run&.workflow&.name || notification.title, household_id: notification.household_id,
      data: {
        "title" => notification.title, "body" => notification.body, "link" => link(notification.href),
        "severity" => notification.severity.serialize,
        "workflow" => run&.workflow&.name, "event_type" => run&.event_type
      }.compact
    )
  end

  # Sends one event, or records why it could not. Returns what happened so a
  # workflow step can say so in its run log.
  sig do
    params(type: String, id: String, subject: String, data: T::Hash[String, T.untyped], household_id: T.untyped)
      .returns(Outcome)
  end
  def self.publish(type:, id:, subject:, data:, household_id:)
    client = FogEventsClient.from_env
    return Outcome::Unavailable if client.nil?

    client.publish(type: type, id: id, subject: subject, data: data)
    Outcome::Published
  rescue FogEventsClient::Error => e
    Activity.record(source: "fog", event: "event.failed", severity: Severity::Warning,
                    summary: "fog event #{type} failed: #{e.message}", exception: e, household_id: household_id)
    Outcome::Failed
  end

  # `fin.<suffix>`, folded into fog's type alphabet: "Budget Alerts!" →
  # "fin.budget-alerts".
  sig { params(suffix: String).returns(String) }
  def self.type_for(suffix)
    folded = suffix.downcase.gsub(/[^a-z0-9._-]+/, "-").gsub(/\A[^a-z0-9]+|[-.]+\z/, "")
    folded = "event" if folded.empty?
    "fin.#{folded}".first(128)
  end

  # Joins the parts into an id, hashing it when it would exceed fog's bound.
  sig { params(parts: T.untyped).returns(String) }
  def self.event_id(*parts)
    id = parts.join("-")
    id.length <= MAX_ID_LENGTH ? id : "fin-#{Digest::SHA256.hexdigest(id)}"
  end

  # An in-app path made absolute against this instance's configured origin,
  # so a reader can open it. Nil when Fin can't know its own address (no
  # configured origin), and absolute URLs pass through.
  sig { params(href: T.nilable(String)).returns(T.nilable(String)) }
  def self.link(href)
    return nil if href.blank?
    return href if href.match?(%r{\Ahttps?://})

    origin = ENV["FIN_WEBAUTHN_ORIGINS"].to_s.split(",").map(&:strip).find { |o| o.match?(%r{\Ahttps?://[^/]+\z}) }
    origin ||= ENV["FIN_WEBAUTHN_RP_ID"].presence&.then { |host| "https://#{host}" }
    return nil if origin.nil?

    "#{origin}#{href.start_with?('/') ? '' : '/'}#{href}"
  end
end
