# Price consolidation, stage 2 (see docs/price-consolidation.md).
#
#   bin/rails market_data:backfill_candles        # idempotent, resumable
#   bin/rails market_data:verify_candle_backfill  # prints rows still uncovered
#
# Custodian prices (see MarketData::CustodianPrices):
#
#   bin/rails market_data:backfill_custodian_prices  # idempotent
namespace :market_data do
  desc "Copy market_prices rows the candle store doesn't cover into daily candles (idempotent)"
  task backfill_candles: :environment do
    inserted = MarketData::LegacyCandleBackfill.run(log: ->(message) { puts message })
    puts "inserted #{inserted} candles; #{MarketData::LegacyCandleBackfill.uncovered_count} market_prices rows still uncovered"
  end

  desc "Count market_prices rows with no daily candle (0 means stage 2 can proceed)"
  task verify_candle_backfill: :environment do
    puts "#{MarketData::LegacyCandleBackfill.uncovered_count} market_prices rows have no daily candle"
  end

  desc "Seed custodian closes from surviving position snapshots for instruments no provider prices (idempotent)"
  task backfill_custodian_prices: :environment do
    totals = MarketData::CustodianPriceBackfill.run(log: ->(message) { puts message })
    puts "wrote #{totals[:closes]} custodian closes for #{totals[:securities]} instruments"
  end
end
