# typed: strict

require "bigdecimal"

module Importers
  # The one transaction layout Fin accepts from a hand-kept spreadsheet —
  # an Office sheet, or anything saved as CSV — as opposed to the bank
  # exports the other importers recognise by their exact headers.
  #
  # Headers match by name, ignoring case and surrounding spaces, so "date"
  # and " Date " both work, but a different word never does: "Payee" is
  # offered as a rename to "Description" rather than silently accepted, so
  # what a column means is never a guess. The column list here is what the
  # import modal shows (GET /api/v1/imports/format) and what the preview and
  # the importer check against, so the three can't disagree.
  module SpreadsheetFormat
    extend T::Sig

    class Column < T::Struct
      const :name, String
      const :required, T::Boolean
      const :description, String
      const :example, String
    end

    COLUMNS = T.let(
      [
        Column.new(name: "Date", required: true, example: "01/31/2026",
                   description: "When the transaction happened. 01/31/2026, 1/31/26 or 2026-01-31; a cell formatted as a date works too."),
        Column.new(name: "Description", required: true, example: "Trader Joe's",
                   description: "What the transaction was. Merchant rules match against this."),
        Column.new(name: "Amount", required: true, example: "-54.20",
                   description: "Negative for money out (purchases, withdrawals), positive for money in (deposits, refunds, card payments). " \
                                "$, thousands commas and (54.20) for negatives are fine."),
        Column.new(name: "Post Date", required: false, example: "02/01/2026",
                   description: "When it posted, if different from Date."),
        Column.new(name: "Category", required: false, example: "Groceries",
                   description: "A Fin category name. Used when no merchant rule matches; unknown names are ignored."),
        Column.new(name: "Type", required: false, example: "Sale",
                   description: "Sale, Return or Payment. Left blank, Fin works it out from the amount and description."),
        Column.new(name: "Memo", required: false, example: "Split with Sam",
                   description: "A note kept on the transaction."),
        Column.new(name: "Balance", required: false, example: "1,204.33",
                   description: "The running balance after this row, if the sheet tracks one.")
      ].freeze,
      T::Array[Column]
    )

    # Amount can instead come as two unsigned columns, the way a paper
    # ledger is often kept: Debit is money out, Credit is money in.
    DEBIT  = "Debit"
    CREDIT = "Credit"
    SPLIT_AMOUNT_HELP = "Instead of Amount, a sheet may use Debit (money out) and Credit (money in) columns of positive numbers."

    # Headers people commonly use for the required columns, offered as
    # renames when the real name is missing. Keys are normalized.
    RENAMES = T.let(
      {
        "Date"        => [ "transaction date", "trans date", "trade date", "posted date", "posting date", "day", "when" ],
        "Description" => [ "payee", "merchant", "name", "details", "transaction", "narrative", "item", "vendor" ],
        "Amount"      => [ "amt", "value", "total", "sum", "amount usd", "amount ($)", "transaction amount", "net" ],
        DEBIT         => [ "withdrawal", "withdrawals", "debits", "money out", "spent", "outflow", "charge", "charges" ],
        CREDIT        => [ "deposit", "deposits", "credits", "money in", "received", "inflow" ]
      }.freeze,
      T::Hash[String, T::Array[String]]
    )

    DATE_PATTERNS = T.let(
      [
        [ /\A\d{4}-\d{1,2}-\d{1,2}\z/, "%Y-%m-%d" ],
        [ %r{\A\d{1,2}/\d{1,2}/\d{4}\z}, "%m/%d/%Y" ],
        [ %r{\A\d{1,2}/\d{1,2}/\d{2}\z}, "%m/%d/%y" ]
      ].freeze,
      T::Array[[ Regexp, String ]]
    )

    # Spreadsheets store a date as days since 1899-12-30, and Office's
    # read_sheet hands back that raw number for a date-formatted cell. The
    # window keeps a stray amount from reading as a date: 1990 to 2100.
    SERIAL_EPOCH = T.let(Date.new(1899, 12, 30), Date)
    SERIAL_RANGE = T.let(32_874..73_051, T::Range[Integer])

    sig { params(header: T.untyped).returns(String) }
    def self.normalize(header)
      header.to_s.delete_prefix("﻿").strip.downcase.gsub(/\s+/, " ")
    end

    # Canonical column name => the header as the sheet spells it, for the
    # columns this format knows.
    sig { params(headers: T::Array[T.untyped]).returns(T::Hash[String, String]) }
    def self.index(headers)
      known = (COLUMNS.map(&:name) + [ DEBIT, CREDIT ]).index_by { |name| normalize(name) }
      headers.each_with_object({}) do |header, found|
        name = known[normalize(header)]
        found[name] ||= header.to_s if name
      end
    end

    sig { params(headers: T::Array[T.untyped]).returns(T::Boolean) }
    def self.matches?(headers)
      missing(headers).empty?
    end

    # Required columns the header row lacks. Amount counts as present when
    # either Debit or Credit is there instead.
    sig { params(headers: T::Array[T.untyped]).returns(T::Array[String]) }
    def self.missing(headers)
      found = index(headers)
      COLUMNS.select(&:required).map(&:name).reject do |name|
        found.key?(name) || (name == "Amount" && (found.key?(DEBIT) || found.key?(CREDIT)))
      end
    end

    # { from: "Payee", to: "Description" } for each missing column some
    # header looks like it means.
    sig { params(headers: T::Array[T.untyped]).returns(T::Array[T::Hash[Symbol, String]]) }
    def self.suggestions(headers)
      found = index(headers)
      taken = found.values.map { |h| normalize(h) }.to_set
      missing(headers).filter_map do |name|
        header = headers.find { |h| !taken.include?(normalize(h)) && RENAMES.fetch(name, []).include?(normalize(h)) }
        next unless header

        taken << normalize(header)
        { from: header.to_s.strip, to: name }
      end
    end

    # The sheet's row as canonical column name => raw cell text.
    sig { params(row: T.untyped).returns(T::Hash[String, T.nilable(String)]) }
    def self.values(row)
      pairs = row.respond_to?(:to_h) ? row.to_h : row
      found = index(pairs.keys)
      found.to_h { |name, header| [ name, pairs[header]&.to_s ] }
    end

    sig { params(value: T.untyped).returns(T.nilable(Date)) }
    def self.parse_date(value)
      text = value.to_s.strip.split(/[ T]/).first.to_s
      return nil if text.empty?

      if text.match?(/\A\d+(\.\d+)?\z/)
        serial = text.to_f.floor
        return SERIAL_RANGE.cover?(serial) ? SERIAL_EPOCH + serial : nil
      end

      pattern = DATE_PATTERNS.find { |regex, _| text.match?(regex) }
      pattern ? Date.strptime(text, pattern[1]) : nil
    rescue Date::Error
      nil
    end

    # "-1,204.50", "$54.20", "(54.20)" and "-$54.20" all read; anything else
    # with letters in it doesn't.
    sig { params(value: T.untyped).returns(T.nilable(BigDecimal)) }
    def self.parse_amount(value)
      text = value.to_s.strip
      return nil if text.empty?

      negative = text.start_with?("(") && text.end_with?(")")
      text = text[1..-2].to_s if negative
      text = text.delete("$,").delete(" ")
      return nil unless text.match?(/\A[+-]?\d*\.?\d+\z/)

      amount = BigDecimal(text)
      negative ? -amount.abs : amount
    rescue ArgumentError
      nil
    end

    # The row's signed amount, from Amount or from Debit/Credit. Returns
    # [amount, problem]; one of the two is nil.
    sig { params(values: T::Hash[String, T.nilable(String)]).returns([ T.nilable(BigDecimal), T.nilable(String) ]) }
    def self.amount(values)
      if values.key?("Amount")
        raw = values["Amount"].to_s.strip
        return [ nil, "Amount is blank" ] if raw.empty?

        parsed = parse_amount(raw)
        return parsed ? [ parsed, nil ] : [ nil, "“#{raw}” in Amount isn't a number" ]
      end

      debit_raw  = values[DEBIT].to_s.strip
      credit_raw = values[CREDIT].to_s.strip
      return [ nil, "Debit and Credit are both blank" ] if debit_raw.empty? && credit_raw.empty?

      debit  = debit_raw.empty?  ? BigDecimal(0) : parse_amount(debit_raw)
      credit = credit_raw.empty? ? BigDecimal(0) : parse_amount(credit_raw)
      return [ nil, "“#{debit_raw}” in Debit isn't a number" ] if debit.nil?
      return [ nil, "“#{credit_raw}” in Credit isn't a number" ] if credit.nil?

      [ credit.abs - debit.abs, nil ]
    end

    # Everything wrong with one row, as messages a person can act on.
    sig { params(values: T::Hash[String, T.nilable(String)]).returns(T::Array[String]) }
    def self.row_problems(values)
      problems = []
      raw_date = values["Date"].to_s.strip
      if raw_date.empty?
        problems << "Date is blank"
      elsif parse_date(raw_date).nil?
        problems << "“#{raw_date}” in Date isn't a date Fin reads (use 01/31/2026 or 2026-01-31)"
      end
      raw_post = values["Post Date"].to_s.strip
      if raw_post.present? && parse_date(raw_post).nil?
        problems << "“#{raw_post}” in Post Date isn't a date Fin reads"
      end
      problems << "Description is blank" if values["Description"].to_s.strip.empty?
      _, amount_problem = amount(values)
      problems << amount_problem if amount_problem
      problems
    end

    # Bank or card activity: an account keeps whatever its existing rows
    # are, and a new one is a card when its type says so. Card rows count
    # toward spend by Type, bank rows by sign (CashTransaction.spend_like),
    # so this decides how the import reads in cashflow.
    sig { params(account: T.untyped).returns(String) }
    def self.source_for(account)
      return "bank" if account.nil?

      existing = ::CashTransaction.where(account_id: account.id).group(:source).order(Arel.sql("COUNT(*) DESC")).limit(1).pluck(:source).first
      return existing.to_s if existing

      account.account_type.to_s.match?(/credit/i) ? "credit_card" : "bank"
    end

    # Type as Plaid ingest assigns it (Plaid::TransactionSync), from the
    # sign and the descriptor, when the sheet doesn't say.
    sig { params(amount: BigDecimal, description: T.nilable(String), source: String).returns(String) }
    def self.inferred_type(amount, description, source)
      if source == "credit_card" && amount.positive? && ::Transfers::PaymentSignals.signature?(description)
        return ::CashTransaction::TransactionType::Payment.serialize
      end

      (amount.positive? ? ::CashTransaction::TransactionType::Return : ::CashTransaction::TransactionType::Sale).serialize
    end

    # The format as the import modal describes it.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def self.describe
      {
        columns: COLUMNS.map do |c|
          { name: c.name, required: c.required, description: c.description, example: c.example }
        end,
        split_amount: SPLIT_AMOUNT_HELP,
        notes: [
          "Column names go in row 1, one transaction per row below. Extra columns are ignored.",
          "Names match ignoring case and spaces, but must otherwise be spelled as shown.",
          "Re-importing the same rows skips the ones already in the account, so a fixed-up sheet can be imported again."
        ]
      }
    end
  end
end
