# typed: strict

require "csv"

module Importers
  # Peeks at the CSV's first row, sets csv_import.kind, and delegates to the
  # matching importer.
  class Dispatcher < T::Struct
    class UnknownFormatError < StandardError; end

    # A filesystem path, or an IO-ish that responds to #gets/#rewind
    # (ActiveStorage's `file.open` yields a Tempfile, which is not an IO).
    const :source, T.any(IO, StringIO, Tempfile, String, Pathname)
    const :csv_import, T.nilable(CsvImport)
    # Custodian NAME for broker/holdings rows (imports pass
    # csv_import.broker_name through), not a Broker record.
    const :default_broker, T.nilable(String), default: nil
    const :target_account, T.nilable(Account), default: nil

    # Returns whatever the delegated importer's #call returns
    # (Importers::Result in production; specs stub the importers).
    sig { returns(T.untyped) }
    def call
      headers = read_headers
      kind = self.class.kind_for(headers)
      csv_import&.update!(kind: kind.serialize)

      case kind
      when Kind::Transactions
        Importers::BrokerCsv.new(source: source, csv_import: csv_import, default_broker: default_broker).call
      when Kind::Holdings
        Importers::HoldingsCsv.new(source: source, csv_import: csv_import, default_broker: default_broker, target_account: target_account).call
      when Kind::CreditCard
        Importers::CreditCardCsv.new(source: source, csv_import: csv_import, account: target_account).call
      when Kind::Checking
        Importers::CheckingCsv.new(source: source, csv_import: csv_import, account: target_account).call
      when Kind::Spreadsheet
        Importers::SpreadsheetCsv.new(source: source, csv_import: csv_import, account: target_account).call
      when Kind::Unknown
        raise UnknownFormatError, self.class.unknown_message(headers)
      else
        T.absurd(kind)
      end
    end

    sig { params(headers: T::Array[T.nilable(String)]).returns(Kind) }
    def self.kind_for(headers)
      # Broker and checking exports both carry "Trade Date" + "Tran Code";
      # only broker rows have securities columns like "Quantity".
      return Kind::Transactions if headers.include?("Trade Date") && headers.include?("Quantity")
      return Kind::Checking     if headers.include?("Trade Date") && headers.include?("Tran Code")
      return Kind::Transactions if headers.include?("Trade Date")
      return Kind::Holdings     if headers.include?("Asset Class") && headers.include?("Pricing Date")
      return Kind::CreditCard   if headers.include?("Transaction Date") && headers.include?("Post Date")
      # Last: the bank exports above all carry their own Description and
      # Amount-ish columns, and their exact headers are the stronger signal.
      return Kind::Spreadsheet  if SpreadsheetFormat.matches?(headers)
      Kind::Unknown
    end

    # What to change, for a header row that matches nothing: the
    # spreadsheet layout's missing columns, and any header that looks like
    # it means one of them.
    sig { params(headers: T::Array[T.nilable(String)]).returns(String) }
    def self.unknown_message(headers)
      found = headers.compact.map(&:strip).reject(&:empty?)
      return "The file is empty — row 1 should hold the column names (Date, Description, Amount)." if found.empty?

      missing = SpreadsheetFormat.missing(headers)
      renames = SpreadsheetFormat.suggestions(headers).map { |s| "rename “#{s[:from]}” to “#{s[:to]}”" }
      message = "Unrecognized file. Row 1 has #{found.take(6).join(', ')}#{found.size > 6 ? ', …' : ''}; " \
                "a spreadsheet import needs #{missing.join(', ')} as well."
      renames.any? ? "#{message} Try: #{renames.join('; ')}." : message
    end

    private

    sig { returns(T::Array[T.nilable(String)]) }
    def read_headers
      src = source
      line = case src
      when String, Pathname
        File.open(src, &:gets)
      else
        src.rewind
        first = src.gets
        src.rewind
        first
      end
      line = line.to_s.dup
      line.force_encoding("ASCII-8BIT")
      line.sub!(/\A\xEF\xBB\xBF/n, "")
      line.force_encoding("UTF-8")
      CSV.parse_line(line.strip) || []
    end
  end
end
