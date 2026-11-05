# typed: strict

module Importers
  class CreditCardCsv < T::Struct
    include RowImport
    Result = Importers::Result

    const :source, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :csv_import, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :account, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps

    private

    sig { params(row: CSV::Row, result: T.untyped).void }
    def import_row!(row, result)
      hash = dedup_row_hash(row, scope: account&.id)

      if already_imported?(CashTransaction, hash, row)
        result.skipped += 1
        return
      end

      description  = row["Description"].presence
      raw_category = row["Category"].presence
      payment      = row["Type"].presence == "Payment"
      # Payment legs are money movement, not merchant activity — skip
      # merchant-rule categorization so payment descriptors can't be
      # miscategorized as spending.
      match        = payment ? nil : Merchants::RuleMatcher.match_result(description)
      merchant     = match&.merchant
      category     = match&.category || (payment ? nil : Category.find_by(name: raw_category))

      CashTransaction.create!(
        source:           "credit_card",
        transaction_date: parse_date(row["Transaction Date"]),
        post_date:        parse_date(row["Post Date"]),
        description:      description,
        raw_category:     raw_category,
        transaction_type: row["Type"].presence,
        amount:           dec(row["Amount"]),
        memo:             row["Memo"].presence,
        account:          account,
        merchant:         merchant,
        category:         category,
        source_row_hash:  hash
      )

      result.imported += 1
    end
  end
end
