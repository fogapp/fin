# typed: strict

module Api
  module Render
    class Import < Api::Render::Base
      extend T::Sig

      sig { params(import: ::CsvImport).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(import)
        {
          id:               import.id,
          source_filename:  import.source_filename,
          status:           import.status,
          kind:             import.kind,
          broker_name:      import.broker_name,
          target_account_id: import.target_account_id,
          imported_count:   import.imported_count,
          skipped_count:    import.skipped_count,
          error_count:      import.error_count,
          error_log:        import.error_log,
          started_at:       import.started_at,
          finished_at:      import.finished_at,
          created_at:       import.created_at
        }
      end
    end
  end
end
