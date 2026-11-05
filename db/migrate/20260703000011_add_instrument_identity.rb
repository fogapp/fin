# Phase 1 of docs/instruments_platform_design.md: give securities a real
# identity. instrument_class is a validated enum (crypto and equities can
# never collide again — a crypto symbol and an exchange ticker are different
# identifier schemes), and instrument_identifiers is the unique registry of
# every external identifier pointing at a row.
class AddInstrumentIdentity < ActiveRecord::Migration[8.1]
  CLASS_MAP = {
    "crypto"       => "crypto",
    "etf"          => "etf",
    "equity"       => "equity",
    "common stock" => "equity",
    "mutual fund"  => "mutual_fund",
    "fixed income" => "bond",
    "cash"         => "cash_equivalent"
  }.freeze

  def up
    add_column :securities, :instrument_class, :string, null: false, default: "other"
    add_column :securities, :instrument_attributes, :jsonb, null: false, default: {}
    add_index  :securities, :instrument_class

    create_table :instrument_identifiers, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :security_id, null: false
      t.string :scheme, null: false # cusip | isin | figi | ticker | crypto_symbol | plaid_security_id | coinbase_code | cmc_slug
      t.string :value, null: false
      t.timestamps
      t.index %i[scheme value], unique: true
      t.index :security_id
    end
    add_foreign_key :instrument_identifiers, :securities, on_delete: :cascade

    backfill_classes
    dedupe_securities
    backfill_identifiers
    quarantine_contaminated_crypto_prices
  end

  def down
    drop_table :instrument_identifiers
    remove_column :securities, :instrument_class
    remove_column :securities, :instrument_attributes
  end

  private

  def backfill_classes
    say_with_time "backfilling instrument_class from security_type" do
      Security.reset_column_information
      Security.unscoped.find_each do |sec|
        klass = classify(sec.security_type)
        sec.update_columns(instrument_class: klass) if klass != "other"
      end
    end
  end

  def classify(security_type)
    return "other" if security_type.blank?

    key = security_type.to_s.downcase.strip
    return CLASS_MAP[key] if CLASS_MAP.key?(key)
    return "equity"          if key.include?("stock")
    return "cash_equivalent" if key.include?("cash")
    return "bond"            if key.include?("bond") || key.include?("fixed")
    return "mutual_fund"     if key.include?("fund")

    "other"
  end

  # Merge same-class duplicate tickers (created by the disagreeing lookup
  # paths) into the row with the most transaction history.
  def dedupe_securities
    say_with_time "merging duplicate securities" do
      merged = 0
      groups = Security.unscoped.where.not(ticker: [ nil, "" ])
                       .group_by { |s| [ s.ticker.to_s.upcase, s.instrument_class ] }
      groups.each_value do |rows|
        next if rows.size < 2

        keeper = rows.max_by { |s| InvestmentTransaction.unscoped.where(security_id: s.id).count }
        (rows - [ keeper ]).each do |dup|
          Instruments::Merge.call(keep: keeper, remove: dup)
          merged += 1
        rescue => e
          say "merge #{dup.ticker} (#{dup.id}) failed: #{e.message}", true
        end
      end
      merged
    end
  end

  def backfill_identifiers
    say_with_time "backfilling instrument identifiers" do
      count = 0
      Security.unscoped.find_each do |sec|
        identifiers = []
        identifiers << [ "cusip", sec.cusip ] if sec.cusip.present?
        if sec.ticker.present?
          scheme = sec.instrument_class == "crypto" ? "crypto_symbol" : "ticker"
          identifiers << [ scheme, sec.ticker.to_s.upcase.strip ]
        end
        identifiers << [ "cmc_slug", sec.slug ] if sec.slug.present?

        identifiers.each do |scheme, value|
          InstrumentIdentifier.create!(security_id: sec.id, scheme: scheme, value: value)
          count += 1
        rescue ActiveRecord::RecordNotUnique
          say "identifier collision: #{scheme}:#{value} already registered (security #{sec.id})", true
        end
      end
      count
    end
  end

  # Crypto price history is untrustworthy: the Alpha Vantage sweep has been
  # interleaving same-ticker ETF closes with CoinMarketCap spot prices on the
  # same rows, with no source column to separate them. Wipe crypto history —
  # the 4-hourly CMC sync repopulates today forward, and phase 2's provider
  # backfill restores history from a crypto-native source.
  def quarantine_contaminated_crypto_prices
    say_with_time "deleting contaminated crypto price history" do
      crypto_ids = Security.unscoped.where(instrument_class: "crypto").ids
      MarketPrice.unscoped.where(security_id: crypto_ids).delete_all
    end
  end
end
