# typed: strict

module Importers
  class BrokerCsv < T::Struct
    include RowImport
    Result = Importers::Result

    # `source` is either a filesystem path (String/Pathname) or an IO that
    # responds to #read. `csv_import` is an optional CsvImport record to
    # update with status, counts, and error log.
    const :source, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :default_broker, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :csv_import, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps

    private

    sig { params(row: CSV::Row, result: T.untyped).void }
    def import_row!(row, result)
      raise "default_broker is required (custodian for the account)" if default_broker.blank?

      # The row content includes the account number, so no extra scope needed.
      hash = dedup_row_hash(row)
      if already_imported?(InvestmentTransaction, hash, row)
        result.skipped += 1
        return
      end

      broker  = Broker.find_or_create_by!(name: default_broker)
      account = Account.find_or_create_by!(broker: broker, account_number: row["Account Number"]) do |a|
        a.name = row["Account Name"]
        a.account_type = row["Account Type"]
      end
      security = find_or_create_security(row)
      ttype = TransactionType.find_or_create_by!(code: row["Tran Code"]) do |t|
        t.code_description = row["Tran Code Description"]
        t.category = row["Type"]
      end

      InvestmentTransaction.create!(
        account: account,
        security: security,
        transaction_type: ttype,
        trade_date:        parse_date(row["Trade Date"]),
        post_date:         parse_date(row["Post Date"]),
        settlement_date:   parse_date(row["Settlement Date"]),
        local_currency:    row["Local Currency"].presence,
        price_usd:         dec(row["Price USD"]),
        price_local:       dec(row["Price Local"]),
        quantity:          dec(row["Quantity"]),
        cost_usd:          dec(row["Cost USD"]),
        cost_local:        dec(row["Cost Local"]),
        gl_short_usd:      dec(row["G/L Short USD"]),
        gl_short_local:    dec(row["G/L Short Local"]),
        gl_long_usd:       dec(row["G/L Long USDs"] || row["G/L Long USD"]),
        gl_long_local:     dec(row["G/L Long Local"]),
        amount_usd:        dec(row["Amount USD"]),
        amount_local:      dec(row["Amount Local"]),
        income_usd:        dec(row["Income USD"]),
        income_local:      dec(row["Income Local"]),
        balance:           dec(row["Balance"]),
        commissions_usd:   dec(row["Commissions USD"]),
        commissions_local: dec(row["Commissions Local"]),
        description:       row["Description"].presence,
        check_number:      row["Check Number"].presence,
        tax_withheld:      dec(row["Tax Withheld"]),
        executing_dealer:  row["Broker"].presence,
        source_row_hash:   hash
      )
      result.imported += 1
    end

    sig { params(row: CSV::Row).returns(T.nilable(Security)) }
    def find_or_create_security(row)
      cusip = row["Cusip"].presence
      ticker = row["Ticker"].presence
      return nil if cusip.blank? && ticker.blank?

      security = Instruments::Resolver.resolve!(
        instrument_class: Instruments::Resolver.classify_free_form(row["Security Type"]),
        ticker:           ticker,
        cusip:            cusip,
        name:             Security.sanitize_name(row["Description"]),
        security_type:    row["Security Type"].presence
      )
      clean = Security.sanitize_name(row["Description"])
      security.update!(name: clean) if clean.present? && security.junk_name?
      security
    end
  end
end
