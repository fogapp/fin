# Price consolidation: candles replace market_prices

Status: **stage 1 shipped** (every write goes through `MarketData::CandleWriter`,
every reader in the app goes through `MarketData::PriceSeries` / `OhlcvSeries`,
and on-demand syncs route like the nightly scheduler). Stage 2 is the checklist
below.

## Why

Prices lived in two tables with two sync paths. The on-demand
`MarketPriceSyncer` always called Alpha Vantage and wrote only `market_prices`,
so a newly watched security got no candles (and nothing at all on a
Tiingo-only deploy), while the nightly `MarketData::Scheduler` wrote candles and
each provider copied its rows back into `market_prices`. Readers were split
between the two, and the unadjusted legacy closes drew split cliffs wherever
they were read directly.

## Stage 1 (done)

- `MarketData::CandleWriter` is the only writer: candles, corporate actions,
  and — for now — the legacy `market_prices` copy (`write_legacy!`, marked as
  the stage-2 removal point). Alpha Vantage, Tiingo, CoinGecko and the
  CoinMarketCap spot write all go through it.
- `SyncSecurityPricesJob` syncs through `Router.link_for` +
  `Scheduler.sync_candles!`; `MarketPriceSyncer` is gone.
- Readers moved to `PriceSeries` (which merges both tables, candles winning a
  shared date): the market list (latest price, YTD change), `DailyStats`
  sparklines, the security page price chart (via `OhlcvSeries`), benchmarks,
  and the computed-position price in `RecalculatePositionService`.
  `Security#latest_price` was removed.
- `CrossCheck` reads secondary closes through each provider's read-only
  `fetch_closes`.

## Stage 2 checklist

1. Deploy stage 1 and let one nightly sync run.
2. Backfill candles from legacy rows (idempotent; rerun until it inserts 0):

   ```bash
   bin/rails market_data:backfill_candles
   bin/rails market_data:verify_candle_backfill   # expect 0
   ```

   Backfilled rows carry `source = 'legacy_market_prices'`. Existing candles are
   never overwritten.
3. Spot-check a few long-history securities: the security page chart and the
   market list should be unchanged (they already read the merged series).
4. Stop the copy-back: delete `CandleWriter.write_legacy!` and its call.
5. Move the last direct `market_prices` readers, which are outside the price
   read path:
   - `Audits::InvestmentTransactions` (the "no prices" check joins
     `market_prices`) should check candles.
   - `SystemHealthController` (the legacy freshness fallback).
   - `PriceSeries` / `OhlcvSeries`: drop the legacy half of each merge.
   - `Instruments::Merge.merge_market_prices`.
   - `Security has_many :market_prices`, the `MarketPrice` model, and its
     factory and specs.
6. Migration: `drop_table :market_prices`. It runs on deploy (`db:prepare`).

The `market_prices` name also survives as a sync *target* string
(`MarketPriceSyncJob`, the workflow `trigger_sync` action, the system-health
job list). That is a label for the nightly candle sync, not the table, and can
stay.
