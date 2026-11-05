# typed: true

# Publishes one in-app Notification to fog's event stream (FogEvents). A job
# so the commit that created the notification — inside a workflow run or a
# request — never waits on fogd; FogEvents records a failure rather than
# raising, so there is nothing to retry into.
class PublishNotificationEventJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { params(notification_id: String).void }
  def perform(notification_id)
    with_record(Notification, notification_id) { |notification| FogEvents.notification(notification) }
  end
end
