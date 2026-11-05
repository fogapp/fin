# typed: strict

require "csv"
require "digest"

module Importers
  Result = Struct.new(:imported, :skipped, :errors, keyword_init: true)

  # Shared scaffolding for the CSV importers: the CsvImport status lifecycle,
  # BOM-safe row enumeration, date/decimal parsing, error formatting, and
  # dedup row hashing. Including classes implement `import_row!(row, result)`
  # and may implement `prepare!` for per-file setup that should fail the
  # import as a whole (e.g. resolving the target account).
  module RowImport
    extend T::Sig

    extend T::Helpers

    # Mixed into T::Struct importers, so Kernel helpers (respond_to?, raise,
    # BigDecimal) resolve through the includer. The includer also supplies
    # csv_import/source (T::Struct props), import_row!, and optionally
    # prepare!; those come in as untyped via `T.bind(self, T.untyped)` in the
    # methods that call them, since T::Struct props can't carry `override.`.
    requires_ancestor { Kernel }

    BOM = T.let("\xEF\xBB\xBF".b, String)

    sig { returns(T.untyped) }
    def call
      T.bind(self, T.untyped) # csv_import/source/import_row!/prepare! come from the includer
      result = Result.new(imported: 0, skipped: 0, errors: [])

      csv_import&.update!(status: :processing, started_at: Time.current,
                          imported_count: 0, skipped_count: 0, error_count: 0,
                          error_log: nil)

      begin
        prepare! if respond_to?(:prepare!, true)
        each_row do |row|
          csv_row = T.cast(row, CSV::Row)
          next if csv_row.to_h.values.all?(&:blank?)
          import_row!(csv_row, result)
        rescue => e
          result.errors << { row: row.to_h, error: e.message }
        end
      rescue => e
        csv_import&.update!(status: :failed, finished_at: Time.current,
                            error_log: "Fatal: #{e.class}: #{e.message}")
        if csv_import
          Activity.record(
            source: "import", event: "import.failed", severity: Severity::Error,
            summary: "CSV import #{csv_import.source_filename} failed: #{e.class}: #{e.message}",
            subject: csv_import
          )
        end
        raise
      end

      csv_import&.update!(
        status: :completed,
        finished_at: Time.current,
        imported_count: result.imported,
        skipped_count: result.skipped,
        error_count: result.errors.size,
        error_log: format_errors(result.errors)
      )

      if csv_import
        Workflows::Events.publish("import.completed", subject: csv_import,
                                  payload: { "kind" => csv_import.kind,
                                             "imported" => result.imported,
                                             "skipped" => result.skipped,
                                             "errors" => result.errors.size })
        Activity.record(
          source: "import", event: "import.completed",
          severity: result.errors.any? ? Severity::Warning : Severity::Info,
          summary: "CSV import #{csv_import.source_filename} (#{csv_import.kind}): " \
                   "#{result.imported} imported, #{result.skipped} skipped" \
                   "#{result.errors.any? ? ", #{result.errors.size} errors" : ''}",
          subject: csv_import,
          payload: { kind: csv_import.kind, imported: result.imported,
                     skipped: result.skipped, errors: result.errors.size }
        )
      end

      result
    end

    private

    sig { params(block: T.proc.params(arg0: T.any(CSV::Row, T::Array[T.untyped])).void).void }
    def each_row(&block)
      T.bind(self, T.untyped) # `source` is supplied by the includer
      if source.respond_to?(:read)
        source.rewind if source.respond_to?(:rewind)
        data = source.read.dup
        data.force_encoding("ASCII-8BIT")
        data.sub!(/\A#{Regexp.escape(BOM)}/, "")
        data.force_encoding("UTF-8")
        CSV.parse(data, headers: true, &block)
      else
        CSV.foreach(source, headers: true, encoding: "bom|utf-8", &block)
      end
    end

    # Accepts "04/19/2026" or "04/17/2026 11:59:59".
    sig { params(value: T.nilable(String)).returns(T.nilable(Date)) }
    def parse_date(value)
      return nil if value.blank?
      value = value.to_s.strip.split(" ").first
      Date.strptime(T.must(value), "%m/%d/%Y")
    rescue Date::Error
      Date.parse(T.must(value)) rescue nil
    end

    sig { params(value: T.untyped).returns(T.nilable(BigDecimal)) }
    def dec(value)
      return nil if value.nil? || value.to_s.strip.empty?
      BigDecimal(value.to_s.gsub(",", ""))
    rescue ArgumentError
      nil
    end

    # The historical content-only hash. Still checked for dedup so files
    # imported before the scoped hash existed aren't re-imported.
    sig { params(row: T.untyped, scope: T.untyped).returns(String) }
    def content_row_hash(row, scope: nil)
      Digest::SHA256.hexdigest([ scope, row.to_h.to_a.sort ].compact.to_s)
    end

    # Dedup hash: row content + import scope (e.g. target account id) + a
    # per-file occurrence counter. The scope lets identical data be imported
    # into two different accounts; the counter lets two legitimately
    # identical rows in one statement (same coffee, same day, same amount)
    # both import instead of the second being silently skipped.
    sig { params(row: T.untyped, scope: T.untyped).returns(String) }
    def dedup_row_hash(row, scope: nil)
      content = row.to_h.to_a.sort.to_s
      key = [ scope, content ]
      @row_occurrences = T.let(@row_occurrences, T.nilable(T::Hash[T.untyped, Integer]))
      @row_occurrences ||= Hash.new(0)
      occurrence = @row_occurrences[key]
      @row_occurrences[key] += 1
      Digest::SHA256.hexdigest([ scope, content, occurrence ].to_s)
    end

    sig { params(model: T.untyped, hash: String, row: T.untyped).returns(T::Boolean) }
    def already_imported?(model, hash, row)
      model.exists?(source_row_hash: hash) ||
        model.exists?(source_row_hash: Digest::SHA256.hexdigest(row.to_h.to_a.sort.to_s))
    end

    sig { params(errors: T.untyped).returns(T.nilable(String)) }
    def format_errors(errors)
      return nil if errors.empty?
      errors.map { |e| "- #{e[:error]}" }.join("\n")
    end
  end
end
