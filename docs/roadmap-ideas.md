# Fin — Future Feature Ideas

**Date:** 2026-07-06. Ambitious but utility-first: everything here should make managing
household finances and investments materially easier. Organized by theme; each item notes
the existing infrastructure it builds on. Tiers: 🟢 near-term (mostly assembled from what
exists), 🟡 medium effort, 🔴 big bet.

## 1. Cashflow intelligence & forecasting

- 🟢 **Expected-cash-events calendar.** Unify subscriptions, detected recurring income,
  loan payments, and recurring transfers (the new `transfer_to_account` workflows) into
  one forward calendar. The subscription detector already computes intervals — extend it
  to income and transfers.
- 🟡 **Balance forecasting.** Project per-account balances 30–90 days out from expected
  events + budget run-rate. The headline feature: *"Checking dips below $500 on Jul 24 —
  the Vanguard transfer lands two days after the mortgage."* Workflow trigger:
  `forecast.low_balance` → notification.
- 🟢 **Price-creep detection.** Alert when a subscription's charge rises vs. its history
  ("Netflix went from $15.49 → $17.99, +16%"). Data already exists in the recurring
  detector; needs a monitor + workflow event.
- 🟡 **Savings goals.** Named targets (emergency fund, vacation) funded by real transfers —
  the new one-sided/external transfer model gives goals an honest ledger. Funding rules as
  workflows (percent of income on payday).
- 🟡 **Year-over-year & seasonal views.** "July vs last July" on every spending chart;
  seasonality overlay (insurance quarters, holiday spike) in cashflow.
- 🔴 **Scenario planner.** "What if we buy a $60k car in March?" — inject hypothetical
  events into the forecast and watch net worth / cashflow / budget absorb them.

## 2. Investments

- 🟢 **Dividend calendar & income projection.** Positions + declared dividends → forward
  12-month income view, per account and per holding. Instruments platform already has the
  identity + price plumbing.
- 🟡 **True performance measurement.** Time-weighted and money-weighted (IRR) returns per
  account/holding/household vs. the benchmarks already in BenchmarkCombobox. Cashflow-aware
  (uses transfers into brokerage accounts — now cleanly modeled).
- 🟡 **Allocation targets & drift.** Set a target mix (equity/bond/cash/crypto, or finer);
  drift dashboard + rebalancing suggestions ("sell $4k VTI in the IRA, not the taxable —
  no gains realized"). Reuses the reconciliation/drift UI patterns.
- 🟡 **Tax-lot intelligence.** The lot editor exists; add: unrealized gain/loss by lot with
  holding-period countdown (short→long), tax-loss-harvesting candidates, wash-sale
  detection (workflow monitor), and a capital-gains what-if calculator for a contemplated
  sale.
- 🟡 **ETF look-through.** Decompose fund holdings to see true sector/region/single-stock
  concentration across the household ("you're 11% NVDA once QQQ and VGT are unpacked").
- 🟢 **Concentration & risk alerts.** Workflow events for position > X% of portfolio,
  single-day moves, 52-week highs/lows on watchlist names.
- 🟡 **Cash drag & rate watcher.** Idle-cash detection across accounts vs. current HYSA /
  T-bill / money-market rates; "sweep suggestion" with a one-click transfer workflow.
- 🟡 **Equity comp.** RSU/ESPP/option grants: vesting schedules on the calendar, sell-to-
  cover modeling, concentration feeding the risk view.
- 🔴 **Retirement / FIRE module.** Monte-Carlo projection from actual balances, savings
  rate, and allocation; safe-withdrawal and coast-FIRE numbers on the dashboard.
- 🔴 **Fixed-income ladders.** CD/T-bill/bond ladder builder and maturity calendar with
  reinvestment prompts.

## 3. Taxes

- 🟡 **Tax center.** YTD realized gains (short/long), dividend classification (qualified vs
  ordinary), estimated quarterly payment tracker, and a per-institution tax-document
  checklist each spring.
- 🟢 **Contribution-limit tracking.** 401k/IRA/HSA/529 progress bars fed by the transfer
  ledger (transfers to those accounts are now first-class, even when external).
- 🟡 **Charitable giving.** Donation tracker (cash + in-kind), receipts attached, DAF
  support; year-end summary export.
- 🔴 **Advisor/CPA export.** One-click annual package: realized gains, income summary,
  Schedule-E-ready rental P&L, document bundle.

## 4. Real estate & household assets

- 🟡 **Property hub.** Each property: valuation history (manual + optional AVM fetch),
  mortgage link (loans exist), equity contribution to net worth, cost basis +
  capital-improvements ledger (matters for the sale exclusion someday).
- 🟢 **Maintenance & warranty log.** Dated service records attached to the property,
  reminder workflows ("HVAC service every 12 months").
- 🟡 **Insurance inventory.** Policies (home/auto/umbrella/life) with premiums, renewal
  alerts, and premium-creep detection at renewal.
- 🟡 **Rental support.** Per-property P&L from tagged transactions, security-deposit
  liabilities, occupancy notes.
- 🟢 **Vehicles & big assets.** Depreciating asset entries in net worth with simple curves.

## 5. Household operations & collaboration

- 🟡 **Per-member views & permissions.** Households exist; add member-scoped visibility
  (kids see allowance accounts only), approval flows for large transfers.
- 🟡 **Shared-expense splitting.** Tag transactions as split with a partner/roommate;
  running settle-up balance; settlement is just a transfer (already modeled, incl.
  external counterparties).
- 🟡 **Document vault.** Statements, receipts, tax docs, closing packages — attached to
  transactions/accounts/properties, OCR'd and searchable.
- 🟢 **Annual review generator.** Auto-written year-in-review: net-worth change, savings
  rate, top categories vs last year, fees paid, wins/flags.
- 🔴 **Estate readiness.** Beneficiary audit per account, emergency-access dossier export
  ("everything a spouse needs in one place"), review-date reminders via workflows.

## 6. Data intelligence

- 🟢 **Anomaly detection.** Duplicate charges, unusually large charges vs merchant
  history, first-seen merchants, gray charges — all as workflow monitors feeding the
  existing notification bell.
- 🟡 **Fee X-ray.** Surface bank fees, fund expense ratios (from instruments data),
  advisory fees; annualize: "you paid $1,842 in fees last year."
- 🟡 **Receipt/email ingestion.** Forward a receipt email → parse, match to a transaction,
  itemize (split the Costco run into groceries vs household).
- 🔴 **Natural-language ledger queries.** "How much has the kitchen remodel cost so far?"
  answered from tagged transactions with cited rows; monthly AI-written digest of notable
  changes. (LLM over MatchQuery, read-only.)

## 7. Workflow platform (the multiplier)

- 🟢 **More triggers**: balance thresholds, forecasted events, price moves, date/anniversary,
  document-received. **More actions**: create transfer, adjust budget line, send email/push,
  create task.
- 🟡 **Backtest mode.** "What would this rule have done over the last 12 months?" — run the
  matcher historically, show the would-be actions before enabling. (Match preview already
  exists; extend to actions.)
- 🟡 **Approval queue.** Workflows can propose instead of act; a review inbox like the
  transfer candidates queue.
- 🟢 **Template gallery.** Prebuilt workflows: "round up to savings," "flag charges > $500,"
  "auto-file credit-card payments as transfers."

## 8. Platform & UX

- 🟡 **Mobile PWA + push.** The notification system exists; add web push and a
  phone-first quick-capture flow (snap receipt, check balances).
- 🟡 **Custom report builder.** Saved, shareable reports over MatchQuery filters; scheduled
  email delivery via workflows.
- 🟢 **Dashboard widgets.** User-arrangeable dashboard drawing from any module (top flow,
  runway, drift, next bills).
- 🟡 **Multi-currency.** Balances already carry currency; extend transactions/reporting
  (fx_rates sync target already exists).
- 🟢 **Transfers phase 2** (deferred from the redesign): auto-upgrade one-sided transfers
  to pairs when the counterpart account syncs; merge external → synced accounts; Plaid
  PFC category signals boosting candidate detection.

## Suggested next three

1. **Expected-cash-events calendar → balance forecasting** (§1) — highest daily utility,
   builds directly on subscriptions + recurring transfers.
2. **Dividend calendar + true performance (TWR/IRR)** (§2) — makes the investments side
   answer its two core questions: what does it pay, and is it working.
3. **Anomaly detection as workflow monitors** (§6) — cheap, uses the engine you already
   trust, and catches real money.
