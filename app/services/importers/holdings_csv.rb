# typed: strict

module Importers
  class HoldingsCsv < T::Struct
    include RowImport
    Result = Importers::Result

    const :source, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :default_broker, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :csv_import, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :target_account, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps

    private

    sig { void }
    def prepare!
      @account = T.let(resolve_account!, T.untyped)
    end

    sig { returns(T.untyped) }
    def resolve_account!
      return target_account if target_account

      raise "Pick an account (or a broker) before uploading a holdings CSV." if default_broker.blank?
      broker = Broker.find_by(name: default_broker)
      raise "No broker named '#{default_broker}'. Import a transactions CSV for this broker first." unless broker

      accounts = broker.accounts.order(:name)
      raise "Broker '#{default_broker}' has no accounts yet. Import a transactions CSV first." if accounts.empty?
      # Holdings CSV doesn't identify an account; use the broker's first one.
      accounts.first
    end

    sig { params(row: T.untyped, result: T.untyped).void }
    def import_row!(row, result)
      account = @account
      ticker = row["Ticker"].presence
      cusip  = row["CUSIP"].presence
      return if ticker.blank? && cusip.blank?

      as_of = parse_date(row["As of"]) || parse_date(row["Pricing Date"])
      raise "no as_of/Pricing Date for row" if as_of.blank?

      security = find_or_create_security(ticker: ticker, cusip: cusip, description: row["Description"])

      # Snapshots dedup on (account, security, as_of_date); the hash only
      # marks content changes. It's scoped to the account so the same
      # holdings row imported into a second account doesn't collide with the
      # global source_row_hash unique index.
      hash = content_row_hash(row, scope: account.id)
      snap = PositionSnapshot.find_or_initialize_by(account: account, security: security, as_of_date: as_of)

      if snap.persisted? && snap.source_row_hash == hash
        result.skipped += 1
        return
      end

      snap.assign_attributes(
        quantity:                 dec(row["Quantity"]),
        price:                    dec(row["Price"]),
        market_value:             dec(row["Value"]),
        cost_basis:               dec(row["Cost"]),
        unit_cost:                dec(row["Unit Cost"]),
        unrealized_gain_loss:     dec(row["Unrealized G/L Amt."]),
        unrealized_gain_loss_pct: dec(row["Unrealized Gain/Loss (%)"]),
        accrued_income:           dec(row["Accrued Income"]),
        est_annual_income:        dec(row["Est. Annual Income"]),
        dividend_yield:           dec(row["Dividend Yield"]),
        asset_class:              row["Asset Class"].presence,
        asset_strategy:           row["Asset Strategy"].presence,
        asset_strategy_detail:    row["Asset Strategy Detail"].presence,
        acquisition_date:         parse_date(row["Acquisition Date"]),
        source_row_hash:          hash
      )
      snap.save!
      # The statement's price is the only history an unlisted holding gets.
      MarketData::CustodianPrices.record!(security, date: as_of, price: snap.price&.to_d,
                                                    quantity: snap.quantity&.to_d, market_value: snap.market_value&.to_d)
      result.imported += 1
    end

    sig { params(ticker: T.untyped, cusip: T.untyped, description: T.untyped).returns(Security) }
    def find_or_create_security(ticker:, cusip:, description:)
      security = Instruments::Resolver.resolve!(
        instrument_class: "other",
        ticker:           ticker,
        cusip:            cusip,
        name:             description&.strip.presence
      )
      # Holdings CSV carries clean company names; upgrade junky names in place.
      security.update!(name: description.strip) if description.present? && security.junk_name?
      security
    end
  end
end
