# typed: strict

module MarketData
  # Seeds custodian closes (MarketData::CustodianPrices) from whatever
  # PositionSnapshot rows survive — holdings-CSV statements keep one row per
  # date, Plaid rows only their latest observation. Idempotent: re-running
  # rewrites the same custodian candles and never touches a date a market
  # provider priced.
  module CustodianPriceBackfill
    extend T::Sig

    # Returns {securities:, closes:} — how many instruments got custodian
    # prices and how many closes were written.
    sig { params(log: T.nilable(T.proc.params(message: String).void)).returns(T::Hash[Symbol, Integer]) }
    def self.run(log: nil)
      securities = 0
      closes = 0

      # Runs outside any household: prices are shared market data.
      security_ids = PositionSnapshot.unscoped.where("price > 0").distinct.pluck(:security_id)
      Security.unscoped.where(id: security_ids).find_each do |security|
        next unless CustodianPrices.eligible?(security)

        rows = PositionSnapshot.unscoped
          .where(security_id: security.id).where("price > 0")
          .order(:as_of_date, :updated_at)
          .pluck(:as_of_date, :price, :quantity, :market_value)
        next if rows.empty?

        # Latest observation per date wins (two accounts, or a re-sync).
        by_date = rows.to_h { |date, price, _qty, _mv| [ date, price.to_d ] }
        written = CustodianPrices.write!(security, by_date.map { |date, price| { date: date, close: price } })

        # Learn the quoting convention from any observation that shows it.
        _date, price, quantity, market_value = rows.reverse.find { |_, _, qty, mv| qty.to_d.nonzero? && mv.to_d.nonzero? }
        if price
          CustodianPrices.remember_quote_basis!(security, price: price.to_d, quantity: quantity.to_d,
                                                        market_value: market_value.to_d)
        end

        next if written.zero?

        securities += 1
        closes += written
        log&.call("#{security.display_name}: #{written} custodian closes")
      end

      { securities: securities, closes: closes }
    end
  end
end
