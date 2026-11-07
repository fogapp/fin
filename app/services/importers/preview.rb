# typed: strict

require "csv"

module Importers
  # A dry read of a file or sheet before it is imported: which format it is,
  # whether its header row is complete, which rows won't import and why, and
  # how the first few rows will land. Nothing is written. The import modal
  # shows this beside each file, so a sheet can be fixed and checked again
  # before anything reaches the ledger.
  class Preview
    extend T::Sig

    SAMPLE_ROWS  = 5
    # Enough to point at the pattern without a wall of red for a sheet
    # whose every date is in the wrong format.
    MAX_PROBLEMS = 20

    LABELS = T.let(
      {
        Kind::Spreadsheet  => "Spreadsheet",
        Kind::Checking     => "Checking account export",
        Kind::CreditCard   => "Credit card export",
        Kind::Transactions => "Brokerage transactions export",
        Kind::Holdings     => "Brokerage holdings export",
        Kind::Unknown      => "Unrecognized"
      }.freeze,
      T::Hash[Kind, String]
    )

    sig { params(csv: String, account: T.untyped).void }
    def initialize(csv:, account: nil)
      @csv     = T.let(csv.dup.force_encoding("UTF-8").delete_prefix("﻿"), String)
      @account = account
      @parse_error = T.let(nil, T.nilable(String))
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def call
      table = parse
      return failure([], "Fin couldn't read this as CSV: #{@parse_error}") if table.nil?

      headers = table.headers.map { |h| h&.to_s }
      return failure(headers, Dispatcher.unknown_message(headers)) if headers.compact.all? { |h| h.strip.empty? }

      kind = Dispatcher.kind_for(headers)
      # Paired with the sheet's row number: row 1 is the header, so the
      # first record is row 2 — the number down the side of the sheet.
      rows = table.each.with_index(2).reject { |row, _| row.fields.all? { |v| v.to_s.strip.empty? } }
      base = {
        format:       kind.serialize,
        format_label: T.must(LABELS[kind]),
        headers:      headers.compact,
        row_count:    rows.size,
        columns:      columns(headers),
        suggestions:  SpreadsheetFormat.suggestions(headers),
        imports_as:   nil,
        sample:       [],
        problems:     [],
        invalid_row_count: 0
      }

      case kind
      when Kind::Unknown
        base.merge(ready: false, problems: [ { row: nil, message: Dispatcher.unknown_message(headers) } ])
      when Kind::Spreadsheet
        base.merge(spreadsheet(rows))
      else
        # A bank or broker export Fin already knows by its exact headers;
        # its importer does its own row checks.
        base.merge(ready: rows.any?, problems: rows.any? ? [] : [ { row: nil, message: "There are no rows under the header." } ])
      end
    end

    private

    sig { returns(T.nilable(CSV::Table)) }
    def parse
      T.cast(CSV.parse(@csv, headers: true), CSV::Table)
    rescue CSV::MalformedCSVError => e
      @parse_error = e.message
      nil
    end

    sig { params(headers: T::Array[T.nilable(String)], message: String).returns(T::Hash[Symbol, T.untyped]) }
    def failure(headers, message)
      {
        format: Kind::Unknown.serialize, format_label: T.must(LABELS[Kind::Unknown]), ready: false,
        headers: headers.compact, row_count: 0, columns: columns(headers), suggestions: [],
        imports_as: nil, sample: [], invalid_row_count: 0,
        problems: [ { row: nil, message: message } ]
      }
    end

    # Each spreadsheet column and the header that filled it, so the modal
    # can tick off what's there and point at what isn't.
    sig { params(headers: T::Array[T.nilable(String)]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def columns(headers)
      found = SpreadsheetFormat.index(headers.compact)
      split = found.key?(SpreadsheetFormat::DEBIT) || found.key?(SpreadsheetFormat::CREDIT)
      SpreadsheetFormat::COLUMNS.map do |column|
        matched = found[column.name]
        if column.name == "Amount" && matched.nil? && split
          matched = [ found[SpreadsheetFormat::DEBIT], found[SpreadsheetFormat::CREDIT] ].compact.join(" / ")
        end
        { name: column.name, required: column.required, found: matched }
      end
    end

    sig { params(rows: T::Array[[ CSV::Row, Integer ]]).returns(T::Hash[Symbol, T.untyped]) }
    def spreadsheet(rows)
      problems = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      sample   = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      invalid  = 0
      source   = SpreadsheetFormat.source_for(@account)

      rows.each do |row, line|
        values = SpreadsheetFormat.values(row)
        found  = SpreadsheetFormat.row_problems(values)
        if found.any?
          invalid += 1
          problems << { row: line, message: found.join("; ") } if problems.size < MAX_PROBLEMS
          next
        end
        next if sample.size >= SAMPLE_ROWS

        amount = T.must(SpreadsheetFormat.amount(values).first)
        description = values["Description"].to_s.strip
        sample << {
          row:         line,
          date:        SpreadsheetFormat.parse_date(values["Date"])&.iso8601,
          description: description,
          amount:      amount.to_f,
          type:        values["Type"].to_s.strip.presence || SpreadsheetFormat.inferred_type(amount, description, source)
        }
      end

      problems.unshift({ row: nil, message: "There are no rows under the header." }) if rows.empty?
      if @account.nil?
        problems.unshift({ row: nil, message: "Pick the account these transactions belong to — a spreadsheet doesn't say." })
      end

      {
        ready:             rows.size > invalid && !@account.nil?,
        imports_as:        @account ? source : nil,
        sample:            sample,
        problems:          problems,
        invalid_row_count: invalid
      }
    end
  end
end
