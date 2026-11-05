# typed: strict

module Importers
  # CSV format detected from the header row. Serializes to the same names
  # as CsvImport's Rails `kind` enum, so `csv_import.kind = kind.serialize`
  # round-trips through the integer-backed column.
  class Kind < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Transactions = new("transactions")
      Holdings = new("holdings")
      CreditCard = new("credit_card")
      Checking = new("checking")
      Spreadsheet = new("spreadsheet")
      Unknown = new("unknown")
    end
  end
end
