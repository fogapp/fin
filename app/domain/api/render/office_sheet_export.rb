# typed: strict

module Api
  module Render
    class OfficeSheetExport < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        scope = ::OfficeSheetExport.all
        scope = scope.for_dataset(params[:dataset]) if params[:dataset].present?
        scope.recent_first.map { |export| serialize(export) }
      end

      sig { params(export: ::OfficeSheetExport).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(export)
        {
          id:               export.id,
          dataset:          export.dataset,
          dataset_label:    export.definition.label,
          title:            export.title,
          document_id:      export.document_id,
          sheet_name:       export.sheet_name,
          url:              export.url,
          filters:          export.filters,
          # Minus the header row: "1,204 transactions" is the number a
          # person means, not 1,205 cells-worth of rows.
          row_count:        [ export.row_count - 1, 0 ].max,
          last_exported_at: export.last_exported_at,
          last_error:       export.last_error,
          created_at:       export.created_at
        }
      end
    end
  end
end
