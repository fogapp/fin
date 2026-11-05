# typed: true

# Tells every household when Fin has been updated. Enqueued each time the
# Solid Queue supervisor boots (config/initializers/solid_queue.rb); the
# unique index on releases.git_sha makes restarts on the same build a no-op,
# so only a boot on a new SHA produces notifications.
class AnnounceReleaseJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { void }
  def perform
    sha = ENV["GIT_SHA"].presence
    return unless sha

    begin
      Release.create!(git_sha: sha)
    rescue ActiveRecord::RecordNotUnique
      return
    end

    each_household do |household|
      Notification.create!(
        household: household,
        title:     "Fin updated",
        body:      "Now running #{sha.first(7)}",
        severity:  Severity::Info,
        href:      "/settings#topic=about"
      )
    end
  end
end
