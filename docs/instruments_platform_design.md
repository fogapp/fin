# Instruments Platform — Market Data Redesign

Status: approved 2026-07-03, implementation in progress. Companion to
docs/workflow_engine_design.md. Based on the four-agent market data audit
(identity, price pipeline, holdings, transaction visibility).

## Why

The audit found the current system has no identity layer (nine disagreeing
Security find_or_create paths, non-unique tickers, security_type set to
"Crypto" by exactly one writer), destructive provider collisions (the daily
Alpha Vantage sweep overwrites CoinMarketCap crypto prices on shared rows —
BTC/ETH are real NYSE tickers), silent ingestion drops (Plaid lookback
window loses posting-lag transactions forever; qualified dividends unmapped;
free-form CSV categories match no view), and a holdings model where Plaid
snapshot rows masquerade as imported batches and evict CSV positions on
every sync, while RecalculatePositionService double-applies quantities.

## Target architecture

1. **Identity**: `instruments` (instrument_class enum: equity, etf,
   mutual_fund, bond, cash_equivalent, crypto, commodity, option, fx,
   real_asset, other; class-typed `attributes` jsonb) +
   `instrument_identifiers` (scheme/value, unique per scheme+value; schemes:
   cusip, isin, figi, ticker [exchange-qualified], crypto_symbol,
   plaid_security_id, coinbase_code, cmc_id, coingecko_id). One
   `InstrumentResolver.resolve!` choke point with precedence
   figi→isin→cusip→ticker+class, normalization, class-conflict detection
   (raise Issue, never adopt), and merge tooling. Route by id everywhere.

2. **Providers**: `MarketData::Provider` capability interface (quotes,
   candles, metadata, news, corporate_actions, fx) +
   `instrument_data_links` (instrument, provider, provider_ref, priority,
   consecutive_failures, last_success_at). Exactly one provider per
   (instrument, capability). Budget-aware scheduler: provider quotas as
   budgets, priority tiers held > watched > benchmark > dormant; dormancy
   pruning; exponential backoff per link.

3. **Price store**: `candles` (instrument, date, ohlcv, adjusted_close,
   currency, source, granularity), `quotes` (latest spot: ts, price,
   currency, source), `corporate_actions` (splits/dividends),
   `fx_rates`. One `PriceSeries` read service applies adjustments + FX.
   Values always carry currency.

4. **Positions engine**: transaction ledger is the source of truth →
   `positions` materialized per (account, instrument) via idempotent
   rebuild (never latest+delta). Custodian statements (CSV/Plaid/Coinbase)
   become `custodian_observations` — dated claims, not positions. A
   reconciliation engine diffs ledger vs latest observation per account →
   findings as Issues + `reconciliation.drift_detected` workflow events.
   Lot engine (FIFO/specific-id) rebuilt from ledger on change,
   coverage-aware, honoring overrides. Single as_of semantics everywhere.

5. **Monitor**: provider health in system_health; price_age staleness on
   every valuation; workflow catalog gains instrument/quote fields for
   alerting; Market page segmented by class; reconciliation inbox;
   valuation history = positions × candles (replaces balance-snapshot
   merging).

## Phases

- **Phase 0 — hotfixes** (committed first; data corrupts daily without):
  crypto excluded from AV sweep + syncer guard; benchmarks NULL-safe
  non-crypto lookup; Plaid maps fixed (cryptocurrency→Crypto, spaced keys,
  qualified dividends→DIV, TransactionType find_or_create, skipped-type
  tally to activity); Plaid investment lookback = last_synced_at − 30d
  overlap, full 2y backfill when the item has zero investment transactions;
  CurrentPositions treats `plaid_holding:` rows as their own species
  (appended, never advancing the imported as_of);
  PositionSnapshot.latest_as_of_date excludes computed rows and the
  account/security-index renderers use CurrentPositions;
  RecalculatePositionService rebuilds from the full ledger keyed on the
  `computed:` hash (idempotent, deletes at net-zero, never adopts foreign
  rows); CMC quotes skip_invalid + symbols limited to crypto accounts;
  failed AV syncs stamp last_synced_at (no quota starvation); Plaid DIV/INT
  set income_usd.
- **Phase 1 — identity core** (+ dedupe migration + contaminated crypto
  price repair via provider re-fetch).
- **Phase 2 — price store + provider router + scheduler.**
- **Phase 3 — positions + reconciliation engine.**
- **Phase 4 — monitor surface + UI.**

Old tables (securities, market_prices, position_snapshots) stay live until
their replacement phase proves out; migrations copy forward, never in
place. The market_prices retirement plan is in
[price-consolidation.md](price-consolidation.md).
