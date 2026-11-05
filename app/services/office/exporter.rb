# typed: strict

require "csv"

module Office
  # Creates and refreshes the spreadsheets Fin keeps in Office.
  #
  # A first export creates a new Office spreadsheet from CSV and records
  # the link (OfficeSheetExport). A refresh rewrites that same document's
  # cells from A1 — so formatting, charts, extra sheets and anything
  # pointing at the document survive, which is the whole reason the link is
  # kept rather than exporting a fresh copy each time.
  class Exporter
    extend T::Sig

    # Errors safe to show the person who pressed the button.
    class Error < StandardError; end

    sig { params(dataset: T.untyped, params: T.untyped, visibility: T.nilable(String), folder_id: T.nilable(Integer)).returns(OfficeSheetExport) }
    def create(dataset:, params:, visibility: nil, folder_id: nil)
      grid = build(dataset, params)

      result = client.create_sheet_from_csv(
        title:      grid.title,
        csv:        self.class.to_csv(grid.rows),
        folder_id:  folder_id || OfficeConfiguration.current.default_folder_id,
        visibility: visibility
      )

      document_id = Integer(result["id"])
      OfficeSheetExport.create!(
        user:             Current.user,
        dataset:          dataset.to_s,
        title:            result["title"].presence || grid.title,
        document_id:      document_id,
        sheet_name:       result["sheet"],
        url:              client.document_url(document_id),
        filters:          grid.filters,
        row_count:        grid.rows.size,
        column_count:     self.class.width(grid.rows),
        last_exported_at: Time.current,
        last_error:       nil
      )
    rescue Office::Client::Error => e
      raise Error, e.message
    end

    # Rebuilds the dataset with the filters the sheet was created from and
    # writes it over the same range.
    sig { params(export: OfficeSheetExport).returns(OfficeSheetExport) }
    def refresh(export)
      grid   = build(export.dataset, export.filter_params)
      values = self.class.pad(grid.rows, height: export.row_count, width: export.column_count)

      client.write_cells(
        document_id: export.document_id,
        values:      values,
        start:       "A1",
        sheet:       export.sheet_name
      )

      export.update!(
        title:            grid.title,
        filters:          grid.filters,
        row_count:        grid.rows.size,
        column_count:     self.class.width(grid.rows),
        last_exported_at: Time.current,
        last_error:       nil
      )
      export
    rescue Office::Client::Error => e
      # Keep the failure on the row: the sheet list is where someone looks
      # to find out why yesterday's refresh didn't land.
      export.update_columns(last_error: e.message.truncate(500), updated_at: Time.current)
      raise Error, e.message
    end

    # Rows padded to the previous extent, so cells that shrank away are
    # cleared (nil blanks a cell) instead of leaving a tail of stale data
    # under the new last row.
    sig do
      params(rows: T::Array[T::Array[T.untyped]], height: Integer, width: Integer)
        .returns(T::Array[T::Array[T.untyped]])
    end
    def self.pad(rows, height: 0, width: 0)
      columns = [ self.width(rows), width ].max
      lines   = [ rows.size, height ].max

      Array.new(lines) do |i|
        row = rows[i] || []
        row + Array.new(columns - row.size, nil)
      end
    end

    sig { params(rows: T::Array[T::Array[T.untyped]]).returns(Integer) }
    def self.width(rows)
      rows.map(&:size).max || 0
    end

    # Values as CSV text for the create path. Dates go out ISO so Office
    # reads them as dates rather than guessing a locale, and nil is an
    # empty field rather than the string "".
    sig { params(rows: T::Array[T::Array[T.untyped]]).returns(String) }
    def self.to_csv(rows)
      CSV.generate do |csv|
        rows.each { |row| csv << row.map { |value| cell(value) } }
      end
    end

    sig { params(value: T.untyped).returns(T.untyped) }
    def self.cell(value)
      case value
      when nil          then nil
      when Date, Time   then value.to_date.iso8601
      when BigDecimal   then value.to_f
      else value
      end
    end

    private

    sig { params(dataset: T.untyped, params: T.untyped).returns(Office::Datasets::Grid) }
    def build(dataset, params)
      Office::Datasets.build(dataset, params)
    rescue ArgumentError => e
      raise Error, e.message
    end

    # Untyped on purpose: specs stub Office::Client.new with a double, as
    # every other provider's specs do, and sorbet-runtime would reject it.
    sig { returns(T.untyped) }
    def client
      @client ||= Office::Client.new
    rescue Office::Client::Error => e
      raise Error, e.message
    end
  end
end
