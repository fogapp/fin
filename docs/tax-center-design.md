# Taxes Page — Design & Implementation Plan

**Date:** 2026-07-06 · **Status:** Built — see `app/services/tax/**` and `Api::V1::Tax::*`
Builds on: tax research (docs/feature-explorations.md §4), exercise-planner engines +
tax_profiles (in flight), equity module, transfers/external accounts, loans, budgets.

## The organizing idea: the Tax Year is a first-class object

A `/taxes` page with a year switcher (the Budget page's month-switcher pattern). Each
year's picture is assembled from three strictly-separated kinds of information, and every
number on the page carries its kind as a badge:

- **FACT** — computed deterministically from ledger data Fin already has
  (realized gains from `gl_short_usd`/`gl_long_usd`, dividend/interest income, per-loan
  mortgage interest, contributions from transfers into retirement accounts, equity events).
- **RECORD** — user bookkeeping the IRS won't tell you (estimated payments made, receipt-
  on-file checkboxes, document checklist state).
- **ESTIMATE** — model output (projected liability, AMT exposure, qualified-dividend
  split), always badged with the assumption set and tax-table vintage.

This is the industry's revealed best practice (Betterment/Wealthfront separate harvested
facts from estimated savings) made structural: the UI can never present an estimate as a
filing number.

## Customization per year

Three escape hatches make any year's situation representable without new code:

1. **`tax_profiles`** (already being built for the planner) — per-year inputs: filing
   status, wages, itemizing/SALT, prior-year tax/AGI, withholding.
2. **`tax_adjustments`** — arbitrary per-year line items {label, kind: income | deduction |
   credit | payment, jurisdiction, amount, notes}. K-1s, rental income, business income,
   anything Fin doesn't model natively flows into the report through here.
3. **Account tax treatment** — new `accounts.tax_treatment` enum (taxable | traditional |
   roth | hsa | education | other). Set once per account; powers contribution tracking now
   and FIRE withdrawal-bucket modeling later.

## Data model (new)

- `accounts.tax_treatment` (string, default "taxable") + UI in the account editor.
- `estimated_tax_payments`: tax_year, jurisdiction (federal|state), paid_on, amount, notes.
- `tax_checklist_items`: tax_year, kind (w2, 1099_consolidated, 1099_int, 1099_r, k1,
  1098, 3921, 3922, 5498, property_tax, charitable_receipt, other), source_label,
  status (expected | received | corrected | n_a), auto_seeded (bool).
  Auto-seeding: one consolidated-1099 per broker with investment activity, a 1098 per
  active loan, a W-2 per profile, a 3921 per ISO exercise event, 5498s per
  traditional/roth account — plus user-added rows.
- `tax_adjustments` (above).
- Parameter store (from the planner) gains the year's contribution limits
  (401k/IRA/HSA/529-gift constants — already researched and verified for 2026).

## Services

**`Tax::YearReport.build(household, year)`** — the one rich assembler (pattern:
`Api::Render::Equity`). Sections:

1. **Income (facts + profile)**: wages (profile — labeled as projection until paystub
   import exists); interest and dividends from `InvestmentTransaction.income` scopes;
   realized capital gains ST/LT from the gl columns with per-lot drill-down; equity-comp
   ordinary income assembled from grant events (NSO exercise spreads, RSU settlements at
   FMV, disqualifying dispositions); adjustments(kind: income).
2. **Deductions (facts + records)**: per-loan YTD mortgage interest (`interest_paid` is
   already computed); SALT paid (CA withholding + state estimated payments + property tax
   adjustments); charitable — transactions in categories flagged charitable (new
   `categories.charitable` boolean) with a receipt-tracking checkbox per $250+ gift;
   adjustments(kind: deduction).
3. **Liability estimate (estimate)**: run `Tax::Federal` + `Tax::California` (the planner's
   engines) over assembled income including this year's actual ISO exercise events → AMT
   exposure — projected total liability, effective + marginal rates, bracket position
   ("$X of 0% LTCG headroom", "$Y until the 24% bracket"), refund/owed projection vs
   withholding + payments.
4. **Payments & safe harbor (records + estimate)**: estimated-payment ledger; the
   planner's safe-harbor module per jurisdiction with per-installment status against the
   real due dates (uneven federal 3/2/3/4; CA 30/40/0/30 + $1M AGI rule); underpayment
   exposure at the current IRC §6621 rate.
5. **Contributions (facts)**: transfers into accounts by tax_treatment vs the year's
   limits — progress bars for 401(k) $24,500 (+catch-up), IRA $7,500, HSA $4,400/$8,750,
   plus 529 gifts vs the $19k exclusion. This is the transfers feature paying off:
   external-account transfers to an unlinked 401(k) count too.
6. **Flags (facts)**: `Tax::WashSaleScanner` — household-wide (the differentiator brokers
   can't match): loss sales vs purchases of the same security ±30 days across ALL
   accounts including IRAs (permanent-disallowance warning per Rev. Rul. 2008-5).
   Warn-only, never silently adjust the gains numbers.
7. **Documents**: the checklist with expected arrival windows (W-2 Jan 31, consolidated
   1099 mid-Feb + corrected-risk note, K-1 late, 5498 May/informational).

**API**: `GET /api/v1/tax/report?year=` (one payload); CRUD for payments, checklist items,
adjustments; `categories/:id` gains the charitable flag; `accounts` gains tax_treatment.

## Page design (`/taxes`, Landmark→Receipt icon, nav group 1)

- **Header**: year switcher (‹ 2026 ›) + "Tax profile" edit (the planner's form, shared).
- **Overview hero**: projected liability (fed + CA) · paid so far (withholding + estimates)
  · **projected refund / amount owed** — the number people actually want — with
  FACT/ESTIMATE badges and the assumptions footer.
- **Section cards** (each linking into the rest of Fin): Income → filtered transaction
  views; Capital gains → lots table; Equity comp → the grant rows + "Plan exercise";
  Deductions → loans page / charitable category; Payments → add-payment dialog + safe
  harbor; Contributions → progress bars linking to accounts; Flags → wash-sale findings;
  Documents → checklist.
- Facts/records/estimates visually distinct throughout; every estimate card shares the
  planner's assumptions-footer component (tables vintage, exclusions, not-tax-advice).

## Workflow integration

New events, all cheap given `Events.publish`: `tax.quarterly_due_approaching` (14 and 3
days before each installment, jurisdiction-aware), `tax.safe_harbor_behind`,
`tax.contribution_limit_approaching` (90% crossed), `tax.document_overdue` (expected
window passed), `tax.wash_sale_detected`. One weekly `TaxScanJob` + due-date checks in the
existing daily scan.

## Phasing

| Phase | Contents | Effort |
|---|---|---|
| **1 — Facts & frame** | Nav + page + year switcher; YearReport income/gains/deductions/contributions facts; `accounts.tax_treatment`; charitable category flag; `tax_adjustments` | ~1.5 wk |
| **2 — Liability & payments** | Engine integration (needs the in-flight planner backend); refund/owed hero; `estimated_tax_payments` + safe-harbor panel + due-date workflow events; equity-comp income + AMT exposure wiring | ~1 wk |
| **3 — Vigilance** | Document checklist (auto-seeded); wash-sale scanner + events; corrected-1099 risk badges; contribution events | ~1 wk |
| **4 — Year-end tools** (later) | Bracket-headroom what-ifs (0% LTCG harvesting, Roth conversion room), CPA export package (PDF/CSV bundle), qualified-dividend 61-day test (needs dividend_events from the dividend-calendar feature) | — |

Phase 1 can start immediately; Phase 2 lands as soon as the exercise-planner backend
merges (its engines, profile, and safe-harbor module are shared foundations).

## What this deliberately does not do

No filing output, no silent wash-sale math, no bare marginal-rate claims, no computed AMT
liability presented as fact (exposure flags + planner scenarios only), qualified-dividend
split always labeled estimate until 1099s arrive. The line, as researched: compute facts
precisely, bound rates pessimistically, never let an estimate look like a filing number.
