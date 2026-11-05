# typed: strict

module Audits
  # Watches CSV imports: stuck-in-processing (over an hour) and recent
  # failures, each surfaced as its own issue.
  class Imports
    extend T::Sig

    sig { void }
    def call
      # Imports stuck in processing for more than an hour
      CsvImport.processing.where("started_at < ?", 1.hour.ago).find_each do |imp|
        Issue.raise_once!(
          key:      "import_stuck:#{imp.id}",
          title:    "Import stuck — #{imp.source_filename}",
          body:     "This import has been processing for over an hour and likely stalled. " \
                    "You may need to re-upload the file.",
          severity: Severity::Error,
          source:   "system_audit"
        )
      end

      # Failed imports from the last 7 days
      CsvImport.failed.where("created_at > ?", 7.days.ago).find_each do |imp|
        Issue.raise_once!(
          key:      "import_failed:#{imp.id}",
          title:    "Import failed — #{imp.source_filename}",
          body:     imp.error_log.presence || "The import failed with no error details recorded.",
          severity: Severity::Error,
          source:   "system_audit"
        )
      end
    end
  end
end
