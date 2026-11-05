# typed: strict

module Importers
  # Transactions from a hand-kept spreadsheet (SpreadsheetFormat): an Office
  # sheet read over MCP, or any sheet saved as CSV. Unlike the bank exports
  # these rows carry no account of their own, so the import is always into
  # the account it was started from.
  class SpreadsheetCsv < T::Struct
    include RowImport
    Result = Importers::Result

    const :source, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :csv_import, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :account, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps

    private

    sig { void }
    def prepare!
      raise ArgumentError, "A spreadsheet import needs an account — start it from the account's Import button" if account.nil?

      @cash_source = T.let(SpreadsheetFormat.source_for(account), T.nilable(String))
    end

    sig { params(row: CSV::Row, result: T.untyped).void }
    def import_row!(row, result)
      values   = SpreadsheetFormat.values(row)
      problems = SpreadsheetFormat.row_problems(values)
      raise ArgumentError, "#{values['Date'].presence || 'undated'} #{values['Description'].to_s.strip}: #{problems.join('; ')}".strip if problems.any?

      hash = dedup_row_hash(row, scope: account.id)
      if already_imported?(CashTransaction, hash, row)
        result.skipped += 1
        return
      end

      source      = T.must(@cash_source)
      description = values["Description"].to_s.strip
      amount      = T.must(SpreadsheetFormat.amount(values).first)
      type        = transaction_type(values["Type"]) || SpreadsheetFormat.inferred_type(amount, description, source)
      payment     = type == CashTransaction::TransactionType::Payment.serialize
      # Payment legs skip merchant-rule categorization (see CreditCardCsv).
      match       = payment ? nil : Merchants::RuleMatcher.match_result(description)
      raw_category = values["Category"].to_s.strip.presence

      CashTransaction.create!(
        source:           source,
        transaction_date: SpreadsheetFormat.parse_date(values["Date"]),
        post_date:        SpreadsheetFormat.parse_date(values["Post Date"]),
        description:      description,
        raw_category:     raw_category,
        transaction_type: type,
        amount:           amount,
        balance:          SpreadsheetFormat.parse_amount(values["Balance"]),
        memo:             values["Memo"].to_s.strip.presence,
        account:          account,
        merchant:         match&.merchant,
        category:         match&.category || (payment || raw_category.nil? ? nil : Category.find_by("LOWER(name) = ?", raw_category.downcase)),
        source_row_hash:  hash
      )

      result.imported += 1
    end

    # The app's own spelling of a Type the sheet gives ("sale" → "Sale"),
    # or the sheet's text as-is for a type Fin has no name for — the
    # column is open, as for the bank importers.
    sig { params(raw: T.nilable(String)).returns(T.nilable(String)) }
    def transaction_type(raw)
      text = raw.to_s.strip
      return nil if text.empty?

      known = CashTransaction::TransactionType.values.map(&:serialize).find { |t| t.casecmp?(text) }
      known || text
    end
  end
end
