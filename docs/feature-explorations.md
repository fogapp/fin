# Feature Explorations — Equity Comp, Dividends, Idle Cash, FIRE, Taxes, Workflow Expansion

**Date:** 2026-07-06 · **Status:** Design exploration. Since built: tax center (§4, see `tax-center-design.md`) and
equity comp (§5, see `exercise-planner-design.md`). Treat the other sections as proposals.

Six features explored via codebase grounding + external research (Carta access, dividend/rate
data sources, FIRE methodology, tax rules — all claims in the underlying research were
source-verified; API behaviors were confirmed with live calls where noted). This doc is the
synthesis: per-feature design, what exists already, what's net-new, effort, and build order.

---

## 0. What the codebase already gives us (the surprises)

- **Dividends already flow into the system.** Alpha Vantage's adjusted daily series populates
  `corporate_actions` (kind=dividend, ex_date, amount); `security_overviews` carries
  `dividend_yield`, `dividend_per_share`, `ex_dividend_date`; `position_snapshots` has
  per-holding `est_annual_income` and `dividend_yield`.
- **Realized-gain math is already columnar.** `investment_transactions` has `gl_short_usd`,
  `gl_long_usd`, `cost_usd`, `income_usd`, `tax_withheld`; `investment_lots` has
  per-lot `acquired_date`/`cost_basis`/`quantity`. A tax center's hardest v1 item is a SUM.
- **FIRE inputs are computed today:** `savings_rate_ytd`, monthly income/spend series
  (`Api::Render::Cashflow`), `net_worth_history`, `portfolio_value_history`.
- **The workflow engine is cheap to extend:** one choke point (`Workflows::Events.publish`),
  a catalog (`APP_EVENTS`/`RECORD_MODELS`), monitors with a 15-min sweep for non-event
  conditions, and a clean action registry. New triggers/actions are each ~a day of work.
- **Net-new infrastructure needed anywhere:** a dividend-events store (richer than
  `corporate_actions`), a reference-rates store (nothing tracks yields/APY today), equity
  grant tables + vesting engine, a Shiller historical dataset, and tax profile/payment tables.

---

## 1. Dividend calendar  — 🟢 readiest, build first

**Data source (verified by live API calls):** Alpha Vantage `function=DIVIDENDS` is free-tier
and returns **forward-declared** dividends with all five fields (ex/declaration/record/pay
dates + amount) — MSFT's response included a fully future row. Gotchas confirmed: missing
dates are the string `"None"`; ETF coverage is good (SCHD complete since 2011) but
`OVERVIEW` is empty for ETFs. Budget: weekly per held symbol ≈ 5–7 requests/day inside the
25/day free cap. Optional layer later: Massive (ex-Polygon) offers one market-wide
"all upcoming dividends" query on its basic tier (re-verify post-rebrand pricing).

**Design:**
- New `dividend_events` table: `security_id, ex_date, pay_date, record_date,
  declaration_date, amount, currency, source, status` (unique `[security_id, ex_date]`).
  Keep `corporate_actions` for splits; migrate its dividend rows in.
- New `dividends` capability on `InstrumentDataLink` + `Router::DEFAULTS`
  (alpha_vantage) + a `sync_dividends` pass in the Scheduler using the existing
  held/watched tiers and backoff machinery.
- **Projection service:** per-holding frequency = median ex-date gap (monthly/quarterly/
  semiannual/annual); variable-payer detection via coefficient of variation of recent
  regular payments (JEPI-style funds project on TTM average, not last×frequency);
  estimated next events = last-year-same-period or last ex + median gap; pay date =
  ex + that holding's median historical ex→pay lag; **exclude specials from projections**.
  Status ladder (industry standard, per Sharesight): Estimated → Declared → Ex-passed →
  Paid — "Paid" reconciles against `InvestmentTransaction.dividends`.
- **UI:** new "Income" section under Investments (SectionLayout pattern): next-12-months
  monthly income bar chart (existing `BarChart`), upcoming-events list with status badges,
  per-holding table (forward yield, yield-on-cost from lots, income contribution %, TTM vs
  forward annual income). SecurityDetail right column gains an "Upcoming dividend" line in
  the existing Dividend Income card. Cheap high-value add: **iCal feed** of ex/pay dates.
- **Workflow events:** `dividend.declared`, `dividend.changed` (cut/raise vs prior regular
  rate — the alert people actually want), `dividend.ex_date_approaching` (monitor-swept).

**Effort:** ~1.5–2 weeks. No unknowns; the data source is verified.

---

## 2. Idle-cash rate watcher — 🟢 small, novel, do second

**Data (verified):** FRED API with one free key covers everything — daily `DGS1MO/DGS3MO/
SOFR`, monthly FDIC `SNDR/MMNDR/NDR12MCD` (~120 req/min limit; must use
`api.stlouisfed.org`, the website blocks non-browsers). Keyless fallbacks confirmed working:
NY Fed `markets.newyorkfed.org/api/rates/all/latest.json` and treasury.gov's daily yield-curve
CSV. **No viable HYSA-rate source exists** (DepositAccounts ToS prohibits scraping) — use
max(3-mo Treasury, SOFR−0.25%) or a user-set reference rate as "achievable yield"; FDIC
national average is only the shame-floor comparison line. Notably: **no open-source PFM
does this at all** — Ghostfolio's emergency-fund rule is a binary check. Genuinely novel.

**Design:**
- New `reference_rates` table (`series, date, value`) — `fx_rates` is the precedent — plus a
  small daily `SyncReferenceRatesJob` (add `rates` to the `trigger_sync` targets).
- Optional `accounts.apy` (user-entered) so the watcher knows which balances are already
  earning.
- **Detection (daily):** monthly spend from trailing 90 days (same basis as budget
  suggestions); per-account buffer = 1 month spend × 1.3, user-overridable; idle = 30-day
  **low-water mark** of (low-yield balances − buffer − tagged emergency fund) — the
  low-water mark is what prevents nagging about money that's about to pay the mortgage.
  Opportunity cost = idle × (reference − account APY).
- **Alerting via the workflow engine, tuned against nagging** (mechanics lifted from
  Betterment/Wealthfront/Fidelity's shipped products): fire `cash.idle_detected` only when
  idle ≥ $1,000 AND opportunity ≥ $50/yr AND persistent ≥ 30 days; snooze 90 days;
  "Mark as intentional" escape hatch (Vanguard: most idle cash is unintentional, but the
  user must be able to disagree). Card copy pattern: *"Checking has averaged $14,200 over
  30 days — $8,700 above your bills + one-month cushion. At 0.01% that earns ~$1/yr; at
  3.9% (3-mo T-bill) it would earn ~$339/yr."* Actions: Adjust buffer / Mark intentional /
  Snooze — and later, a one-click transfer (see §6 `create_transfer`).

**Effort:** ~1 week.

---

## 3. FIRE projections — 🟡 methodology settled, mostly a build

**The research verdict is unusually clear: historical-sequence simulation, not Monte Carlo.**
i.i.d. Monte Carlo destroys mean reversion and demonstrably fattens 30-year tails beyond
anything in 150 years of history (Kitces/Tharp), while getting its inputs right is where
tools publicly stumble (Boldin's 2025 arithmetic-vs-geometric correction). Historical
sequences are deterministic, explainable ("your plan failed only for the 1966 cohort"), and
cross-checkable against cFIREsim/FICalc — which is what users will do. Honesty caveats to
display: ~125 rolling windows ≈ only 4–5 independent ones, and US history is the luckiest
major-market sample (international bootstrap says ~2.3% SWR vs Bengen's new 4.7%). A
credible tool shows results at several withdrawal rates rather than blessing one.

**Design:**
- **Data:** Shiller monthly dataset (shillerdata.com `ie_data.xls`, 1871–present: S&P
  composite, dividends, CPI, GS10, CAPE) vendored as seed data + a refresh task. Synthesize
  bond total returns from GS10 yields exactly as FICalc documents (repricing a par 10-year).
- **Engine (a service, deliberately small):** annual-step loop over ~150 historical cohorts;
  portfolio in three buckets (taxable / tax-deferred / Roth — from `account_type`, plus a
  new Roth flag on accounts); all math in real dollars (deflate by each cohort's actual
  CPI); withdrawals = planned spend + nominal mortgage stream (ends at payoff — loans
  already carry the schedule) − Social Security (user PIA + claiming age; optional 78%
  post-2032 haircut toggle) ± dated one-time events (one generic primitive: amount, date
  or milestone-relative, inflation flag); deferred withdrawals grossed up by an effective
  tax rate; drain taxable → deferred → Roth. Record success, failure year, and minimum
  balance per cohort (magnitude, not just frequency).
- **Dashboard tiles (all inputs already computed by Fin):**
  1. FI numbers at 3.25% / 3.5% / 4% from BOTH trailing-12-month actual spend and a
     user-set planned spend, with a progress bar.
  2. Coast-FIRE curve by age vs projected net worth, with the crossing point (the
     WalletBurst signature chart).
  3. Savings-rate gauge → years-to-FI closed form (t = ln(1 + (1−s)·r/(s·w))/ln(1+r),
     generalized for current portfolio), sensitivity strip at 3/5/7% real.
  4. "X of N historical retirements starting your plan succeeded" + cohort spaghetti chart
     with failing start-years labeled.
  5. Fan chart of real portfolio value (percentile bands across cohorts — no MC needed).
- **Framing rules** (from the research): frequency framing, always pair success % with
  failure magnitude, real dollars everywhere, every assumption visible/editable with source
  notes (Empower's uneditable black box is the named anti-pattern).
- **v2:** block-bootstrap confidence intervals, CAPE-rule display (Shiller data includes
  CAPE), ACA-cliff-aware pre-65 healthcare (the 400% FPL cliff is back in 2026 and is the
  strongest tax incentive early retirees face), Roth conversion ladders, risk-based
  guardrails ("if the portfolio falls to $X, cut spending by $Y").

**Effort:** ~1.5–2 weeks (engine is small; charts are most of it — fan/spaghetti need an
Area/multi-line composition on the existing chart system).

---

## 4. Tax center — 🟡 facts first, estimates labeled

**The industry's revealed principle:** *compute facts precisely, bound rates pessimistically,
never let an estimate look like a filing number.* Betterment shows worst-case rates;
Wealthfront separates fact (losses harvested) from estimate (savings); nobody attempts
mid-year qualified-dividend precision (issuers reclassify after year-end — it's unknowable,
not just hard).

**v1 — deterministic facts (all data exists or arrives with the dividend calendar):**
1. **YTD realized gains** short vs long — direct sums of `gl_short_usd`/`gl_long_usd`, with
   lot-level detail from `investment_lots`.
2. **Cross-account wash-sale warnings** — a genuine differentiator: brokers only check
   per-account; Fin sees the whole household including IRAs (Rev. Rul. 2008-5 —
   an IRA repurchase disallows the loss permanently). Flag, never silently adjust.
3. **Dividends** with a heuristic qualified/ordinary split — the holder-side 61-day test IS
   computable from lots + `dividend_events` ex-dates (build the calendar first); REIT/MMF
   heuristics; always labeled *"estimated — final on 1099-DIV."* Interest in three buckets
   (taxable / Treasury / muni).
4. **Contribution progress bars** — 2026 limits are published constants (401k $24,500 +
   $8,000 catch-up; IRA $7,500; HSA $4,400/$8,750; 415(c) $72,000 mega-backdoor headroom).
   Fed by transfers into Retirement/HSA-typed accounts — the transfer_to_account feature
   is exactly the recognition machinery this needs.
5. **Estimated-payment ledger + safe-harbor tracker** — user enters prior-year total tax and
   AGI → 100%/110% target minus withholding/payments, per-installment status against the
   uneven 2026 due dates (Apr 15 / Jun 15 / Sep 15 / Jan 15 — Q2 is only two months).
   Workflow events: `tax.quarterly_due_approaching`, `tax.safe_harbor_behind`.
6. **Document checklist** by institution with arrival windows (W-2 Jan 31; consolidated
   1099 mid-Feb with corrected-1099 risk badges on REIT/fund accounts; K-1 late; 5498
   informational-only in May) + charitable log with $250+ receipt checkboxes.
- New tables: `tax_profiles` (filing status, state, prior-year tax/AGI),
  `estimated_tax_payments`, year-keyed limit constants. New top-level "Taxes" page.

**v2 — estimation layer, everything badged:** projection-mode quarterly estimates beside the
safe-harbor floor; Betterment-style tax-impact preview on contemplated sales (real lot math,
worst-case rates); "0%-LTCG headroom remaining" style bracket-position displays; equity-comp
hooks (below). **Never ship:** silent wash-sale math, bare marginal-rate claims, computed
AMT liability (flag exposure instead — 2026's 50% phaseout regime makes stale calculators
actively wrong).

**Effort:** v1 ~2 weeks (mostly UI + two small tables; the math is sums).

---

## 5. Equity comp (Carta) — 🔴 biggest build, clearest lane

**The decisive research finding: there is no programmatic path into Carta.** The Portfolio
API is invite-only for SOC 2 Type 2-certified partners; no aggregator covers Carta; even
commercial non-partners (EquityZen, Harness, Monarch) converge on manual entry + document
upload. The employee's **"Individual Ownership Report"** export (Excel; requires the company
to grant cap-table visibility) contains grants, vesting schedules, exercises, and tax
adjustments — but its column headers are publicly undocumented, so build a
**column-mapping importer** (the CSV modal pattern already exists), never a rigid parser.
Employees also cannot export FMV *history* — only current 409A — so a manual FMV table is
required regardless.

**Data model (simplified from the Open Cap Table Format standard):**
- `equity_companies`: name, public flag, optional security link (public), C-corp +
  QSBS-candidate flags, **fmv_history** rows (per-share FMV, effective date, source:
  409A/round/tender; stale badge at +12 months), preferred price.
- `equity_grants`: company, type (ISO/NSO/RSU/RSA), grant_date,
  **vesting_commencement_date** (≠ grant date; anchors tranche math), quantity, strike,
  early_exercisable, double_trigger (private RSUs), expiration_date, PTE window days.
- `vesting_schedules` (reusable templates): flat form {interval, occurrences,
  cliff_installment, allocation: cumulative_rounding} — covers ~95% of grants and the
  rounding rule is load-bearing (5-4-5-4 splits) — plus an explicit per-tranche escape
  hatch for Amazon 5/15/40/40-style curves.
- `equity_grant_events`: exercise (date, qty, method, FMV-at-exercise, 83(b) flag+date),
  vest/settlement (qty, FMV, shares withheld), sale (price, buyer type: tender vs
  third-party — tax character differs), RSU liquidity trigger.
- Derived, never stored: vested quantity as of any date, per-lot basis, holding/QSBS clocks
  (which start at exercise/vest, never grant).

**Product (the verified 20%-for-80%):**
1. Grant registry + vesting engine → vested/unvested as of any date.
2. **Upcoming-vest calendar** feeding workflow events: `equity.vest_upcoming`,
   `equity.grant_expiring`, `equity.pte_started` (90-day ISO→NSO countdown — the alert
   that saves real money).
3. **Two-lane net worth**: vested value (with a user-set tax haircut, default ~25–30%)
   counts; unvested/private "paper value" displays in its own lane and never pollutes net
   worth — private options ≈ $0 until liquid (community consensus). Public-company vested
   shares flow into the normal positions system via `Instruments::Resolver`.
4. **Scenario slider**: "worth at $X/share (or $Y valuation), after estimated tax."
5. Settings → Integrations-style "Equity" area: company editor, FMV history, grant editor
   (~9 fields, mirroring Secfi's validated intake), xlsx/CSV import with mapping preview.
6. **v2 (tax-center hooks, all labeled estimates):** RSU under-withholding gap
   ((marginal − 22%) × vest income — nearly everyone in the 24%+ brackets is
   under-withheld), ISO AMT-headroom *flag* using 2026 OBBBA parameters ($90,100/$140,200
   exemptions, $500k/$1M phaseout at the new 50% rate), QSBS clock tracking (post-7/4/2025
   regime: $15M cap, 3/4/5-year 50/75/100% tiers), concentration alert (employer stock >
   10–15% of net worth).

**Effort:** ~3–4 weeks total (model + engine ~1wk, UI ~1.5wk, importer ~3–4d, workflow
events ~2d). Deliberately skip: ESPP mechanics, SARs, dilution waterfalls, filing output.

---

## 6. Workflow triggers & actions — the connective tissue

Each feature above publishes its own events (one `Events.publish` call + catalog entry
each). Beyond those, generically useful additions:

**Triggers** (APP_EVENTS unless noted): `dividend.declared/changed/ex_date_approaching`,
`cash.idle_detected`, `rate.reference_changed` (threshold-crossing via monitor),
`equity.vest_upcoming/grant_expiring/pte_started`, `tax.quarterly_due_approaching/
safe_harbor_behind`, `budget.month_closed`, plus monitor EXTRA_FIELDS so users can write
their own conditions (`days_until_ex_date`, `idle_cash_usd`, `vested_value_usd`).

**Actions**: `create_transfer` (from/to/amount — powers goal funding and idle-cash sweeps
as *suggestions with approval*, see below), `adjust_budget_line`, `send_email` (distinct
from webhook; SMTP config exists for nothing yet — small lift), and a `propose` wrapper —
**an approval queue** where any action can run in "suggest" mode and land in a review inbox
(the transfer-candidates pattern generalized). That single mechanism converts every
automated money-moving idea from scary to safe.

---

## Recommended build order

| # | Feature | Why this order | Effort |
|---|---|---|---|
| 1 | **Dividend calendar** | Data verified & mostly present; immediate visible value; unlocks tax qualified-split and FIRE income inputs | ~2 wks |
| 2 | **Idle-cash watcher** | Small, novel, exercises new rates infra + workflow events | ~1 wk |
| 3 | **FIRE v1** | Consumes everything existing + dividend income; settled methodology | ~2 wks |
| 4 | **Tax center v1** | Facts-only; benefits from dividend_events; contribution bars ride the transfers feature | ~2 wks |
| 5 | **Equity comp** | Largest and most self-contained; its tax hooks land as tax-center v2 | ~3–4 wks |

Workflow triggers/actions land incrementally inside each feature; the approval-queue action
mechanism is worth building alongside #2 (its first user is the idle-cash sweep suggestion).
