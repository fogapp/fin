# typed: strict

module Importers
  class CheckingCsv < T::Struct
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

      description = row["Description"].presence
      # Payment legs skip merchant-rule categorization (see CreditCardCsv).
      match       = row["Type"].presence == "Payment" ? nil : Merchants::RuleMatcher.match_result(description)
      merchant    = match&.merchant
      category    = match&.category

      CashTransaction.create!(
        source:               "bank",
        transaction_date:     parse_date(row["Trade Date"]),
        post_date:            parse_date(row["Post Date"]),
        description:          description,
        transaction_type:     row["Type"].presence,
        amount:               dec(row["Amount USD"]),
        balance:              dec(row["Balance"]),
        tran_code:            row["Tran Code"].presence,
        tran_code_description: row["Tran Code Description"].presence,
        account:              account,
        merchant:             merchant,
        category:             category,
        source_row_hash:      hash
      )

      result.imported += 1
    end
  end
end
