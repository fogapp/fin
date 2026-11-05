# typed: strict

module Importers
  # Runs a CsvImport whose file is attached: dispatches on the header row,
  # and records a failure on the import rather than raising, so the caller
  # answers with the import either way. Shared by file uploads and Office
  # sheet imports, which differ only in where the CSV came from.
  module Runner
    extend T::Sig

    sig { params(record: CsvImport).returns(CsvImport) }
    def self.run!(record)
      # ActiveStorage's attachment proxy has no RBI; `open` yields a Tempfile.
      T.unsafe(record.file).open do |io|
        Importers::Dispatcher.new(
          source:          io,
          default_broker:  record.broker_name,
          target_account:  record.target_account,
          csv_import:      record
        ).call
      end
      Recurring::DetectJob.perform_later
      record.reload
    rescue Importers::Dispatcher::UnknownFormatError => e
      record.update(status: :failed, kind: :unknown, finished_at: Time.current, error_log: e.message)
      record.reload
    rescue => e
      record.update(status: :failed, finished_at: Time.current, error_log: "#{e.class}: #{e.message}")
      record.reload
    end
  end
end
