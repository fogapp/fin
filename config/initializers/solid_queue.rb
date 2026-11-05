# The supervisor boots once per worker start — i.e. after every deploy — so
# it's where a new release gets announced. The job itself dedupes by SHA.
Rails.application.config.after_initialize do
  SolidQueue::Supervisor.on_start { AnnounceReleaseJob.perform_later }
end
