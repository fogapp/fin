# Credit Card Payments as a First-Class Concept

**Date:** 2026-07-13 · **Status:** Implemented 2026-07-13 (all phases; dev backfill run).
Key entry points: `Transfers::PaymentMatcher` / `Transfers::KindClassifier` /
`Transfers::PaymentSignals` (detection), `Transfers::PaymentMatchJob` (per-row probe,
enqueued from `CashTransaction` after_create_commit), `Transfers::PaymentBackfill` +
`bin/rails payments:backfill` (historical sweep), migration `20260713000001_add_kind_to_transfers`.
Prod rollout: deploy → `bin/rails payments:backfill` → `bin/rails metrics:backfill_all`.
Builds on `docs/transfers-redesign.md` (implemented 2026-07-06); picks up two of its
explicitly deferred items (Plaid PFC as a detection signal; the cashflow transfers bucket)
and supersedes the description-ILIKE payment heuristics in `cash_transactions.rb`.

## The problem

A credit card payment produces two rows: a checking debit (`CHASE CREDIT CRD AUTOPAY`,
−$1,234.56, `source=bank`) and a card credit (`AUTOMATIC PAYMENT - THANK`, +$1,234.56,
`source=credit_card`), typically 1 day apart. Spending is counted at swipe time on the
card, so both payment legs must be cashflow-neutral — but neither leg carries a
structural marker today. The current protection is a brittle stack:

1. **Bank leg** is excluded from `spend_like`/`income_like` only if its description
   matches `ILIKE '%autopay%'` or `'%credit card%'` (`app/models/cash_transaction.rb:50-66`).
   `APPLECARD GSBANK PAYMENT`, `Online Payment ... To ...`, and `PAYMENT THANK YOU`
   descriptions all leak through and **double-count as spend**. In dev data, Apple Card
   payments are counted as spend and miscategorized as "Shopping" by a merchant rule.
2. **Card leg** is excluded only when `transaction_type = 'Payment'`, which PlaidSyncer
   assigns only when PFC primary is `LOAN_PAYMENTS` (`plaid_syncer.rb:351-356`). A card
   credit that falls through becomes `"Return"` and *subtracts* from spend.
3. **Transfers** exclude both legs, but only when confirmed — `DetectTransferCandidatesJob`
   creates unconfirmed candidates that do nothing to the scopes, and in dev **zero** of the
   20 card-side payment credits are transfer-linked. 12 of 20 have an exact-amount
   counterpart within ±5 days; 8 (all on one card) have no synced funding leg at all.

Loan payments have the same shape (mortgage/auto-loan debits typed `Payment` but counted
as spend under whatever category a merchant rule guessed), with one difference: when the
liability's expenses aren't separately tracked, the payment *is* the spend and should
stay countable.

## Design principles (from the transfers research + this data)

- **Identity and treatment are orthogonal.** "This is a credit card payment" (identity)
  and "does it count in cashflow?" (treatment) are separate questions. Tracked-card
  payments are neutral; payments to an *untracked* card are the only visibility into that
  spending and may need to count (cash-basis proxy).
- **Structure over strings.** Description matching is a *detection signal*, never the
  exclusion mechanism. The structural anchor unique to card payments: a positive leg in
  an account of type `Credit Card`. A Zelle payment to a person can never have that, so
  the auto-commit guardrail from the transfers redesign can be safely relaxed *for this
  shape only*.
- **One linking mechanism.** A card payment *is* a transfer between your accounts. Model
  it as a typed `Transfer`, not a parallel system — it inherits pairing, one-sided
  counterparties, confirmation, `transfer_id` exclusion, the review queue, and both
  workflow actions for free.

## Proposed design

### A. `Transfer.kind` — typed transfers

```
transfers.kind                 string  NOT NULL default 'transfer'
                               ∈ { transfer, credit_card_payment, loan_payment }
transfers.confirmation_source  string  ∈ { user, auto, workflow }   (provenance)
transfers.include_in_spend     boolean NOT NULL default false        (treatment, §C)
```

Kind is classified from the legs, not asked of the user:

- `credit_card_payment` — the inflow leg's account is `account_type = 'Credit Card'`
  (or, one-sided, the counterparty account is a credit card / the leg carries payment
  signals §B); the outflow leg is depository.
- `loan_payment` — a leg's account is a liability (`MORTGAGE LOAN`-style, or
  `cash_transactions.loan_id` present), or PFC is `LOAN_PAYMENTS_*` other than the
  credit-card detailed code.
- `transfer` — everything else (unchanged behavior).

Existing transfers are backfilled by re-running the classifier over their legs.

### B. Detection: structural matcher with confidence tiers + safe auto-confirm

Extend `TransferCandidateService` (or a sibling `Payments::Matcher`) with signals:

- **S1 (structural, required):** different accounts; card leg positive in a Credit Card
  account; counterpart depository leg negative; `|sum| < 0.01`; within ±4 days
  (dev data shows 1-day offsets; 4 covers weekends/holidays).
- **S2:** PFC `raw_category = LOAN_PAYMENTS_CREDIT_CARD_PAYMENT` on either leg.
- **S3:** description signature on either leg (`AUTOPAY`, `AUTOMATIC PAYMENT`,
  `PAYMENT THANK YOU`, `EPAY`, `GSBANK PAYMENT`, `CRD AUTOPAY`, …).
- **S4:** cadence — a previously confirmed payment pair exists for the same
  (funding account, card account) pair.

Tiers:

- **S1 + any of S2–S4 → auto-confirm** (`confirmation_source: 'auto'`), immediately
  setting `transfer_id` on both legs. The only S1 false-positive shape is a card refund
  coinciding with an equal unrelated checking debit in the window; refunds carry merchant
  descriptors and no S2/S3/S4, so they stay below the auto line.
- **S1 alone → candidate** (unconfirmed, review queue — today's behavior).
- **One-sided suspects:** a leg with S2/S3 and no counterpart after the window closes
  (card leg with no synced funding account, or bank leg paying an untracked card like
  `APPLECARD GSBANK`) becomes a one-sided *candidate* with a suggested counterparty —
  reusing external accounts from the transfers redesign, with inline "create external
  account 'Apple Card'". Never auto-confirmed; the drawer's "always do this" handoff to
  QuickAutomationModal (`transfer_to_account`) makes it durable after one user decision.

Detection becomes **event-driven**: on `cash_transaction.created`, run the matcher for
that row only (cheap indexed lookup) instead of waiting for a manual `/transfers/scan`.
The late leg (bank side usually posts a day after the card side) triggers the same probe
and — new, promoted from the transfers doc's deferred list — **upgrades an open one-sided
payment into a pair** when it matches an existing one-sided transfer's amount/account/window.

Ingest normalization in `PlaidSyncer` (+ CSV importers):

- Card-account credit with PFC `LOAN_PAYMENTS*` or `TRANSFER_IN` → `transaction_type
  'Payment'` (today's `LOAN_PAYMENTS`-only check misses some; the `"Return"` fallback
  corrupts spend downward). Backfill mislabeled historical rows.
- Payment-classified rows skip merchant-rule categorization (fixes `Online Payment To
  Auto Loan` → "Restaurants").

### C. Treatment: one flag replaces the ILIKE heuristics

`include_in_spend` on the transfer decides cashflow treatment of the **outflow leg**;
inflow legs of any linked transfer are always excluded from income. Scope surgery:

```ruby
# conceptually — the one place exclusion semantics live
scope :income_like, -> {
  source_bank.where("amount > 0")
    .left_joins(:transfer).where(transfers: { id: nil })          # any link excludes inflows
}
scope :spend_like, -> {
  where("(source = 'credit_card' AND transaction_type IN ('Sale','Return')) OR " \
        "(source = 'bank' AND amount < 0)")
    .left_joins(:transfer)
    .where("cash_transactions.transfer_id IS NULL OR (cash_transactions.amount < 0 AND transfers.include_in_spend)")
    # merchant exclusion unchanged
}
```

The description ILIKE filters are **deleted** (kept only as S3 detection signals). Bank
legs are protected by linkage instead of string luck; card legs keep the
`transaction_type` guard as defense-in-depth.

Defaults for the flag, all overridable per transfer:

| Shape | `include_in_spend` | Rationale |
|---|---|---|
| CC payment, both legs tracked | `false` | swipes already counted |
| CC payment, one-sided → external card | `true` | payment is the only spend visibility (cash-basis proxy); leg keeps/gets a category |
| Loan payment | `true` | mortgage/auto payment is budgetable spend (categorize "Housing" etc.) unless the user flips it |
| Generic transfer | `false` | unchanged |

This single flag is what lets the system "explain transactions and how they relate
without double counting": every payment is identified (kind + linkage), and treatment is
an explicit, visible policy instead of an emergent property of description strings.

The window between a bank leg syncing and its pair auto-confirming can still briefly
count as spend; event-driven matching makes this minutes, and a cashflow data-quality
chip ("2 suspected card payments counted in spending — review") surfaces anything that
stays unlinked.

### D. Workflow engine integration

- New events: `transfer.payment_detected` (payload: kind, tier, leg ids) and
  `transfer.auto_confirmed`. Existing `transfer.candidate_detected` unchanged.
- `kind` and `include_in_spend` become condition fields on `Transfer`;
  `transfer_counterpart_count` already exists for CashTransaction.
- `mark_as_transfer` / `transfer_to_account` gain the classifier (kind is set on what
  they create) and an optional `include_in_spend` param.
- Notification copy: "Auto-matched card payment · $1,234.56 · Checking → Visa".

### E. Reporting & UX

- **Badges by kind:** linked rows show "Card payment → Visa" / "Loan payment"
  instead of the generic "Transfer" badge; the existing "Show transfers" toggle governs
  visibility (hidden by default, unchanged).
- **Drawer:** linked payment shows counterparty, provenance ("auto-matched", with
  unlink), and the treatment line — "Not counted in spending" or "Counted as spending
  (Apple Card is untracked)" with a toggle.
- **Transfers page:** scope tabs gain **Card payments** and **Loan payments**; ribbon
  gains "paid to cards this month".
- **Cashflow:** an audit row/section "Credit card payments — $X (not counted)" (the
  deferred net-zero bucket), plus a trailing sanity stat: payments vs. card spend over
  90d (am I paying off what I swipe?).
- **Budget:** no changes — it rides the scopes; loan payments now land under their real
  categories instead of merchant-rule noise.

### F. Backfill & rollout

1. **Schema + classifier** — `kind`, `confirmation_source`, `include_in_spend`;
   backfill kind on existing transfers. (small)
2. **Ingest normalization** — transaction_type fix + payment rows skip merchant rules;
   backfill mislabeled card credits. (small)
3. **Detection** — signals, tiers, event-driven per-row matching, one-sided→pair
   upgrade. Auto-confirm the ~12 clean historical pairs; queue the rest. (medium)
4. **Scope surgery** — structural `spend_like`/`income_like`, delete ILIKEs; recompute
   `metric_points` (historical spend/income series *will* shift — that's the fix, but
   flag it in the release note). (medium, the risky one — parity-spec the before/after
   against known-good months)
5. **UX** — badges, drawer treatment line, tabs, cashflow audit row + review chip. (largest)
6. **Historical sweep on prod** — run the matcher over history, auto-confirm tier-1,
   file Issues for residual one-sided suspects (the 8 card payments funded by an
   unsynced account become one-sided transfers to an external "funding" account or stay
   queued for review).

### Deferred

- Statement-aware reconciliation (match payment amount to statement balance; flag
  partial payments / interest accrual).
- Cash-back / rewards redemptions (`TRANSFER_IN` card credits) as typed income.
- Per-account default overrides for `include_in_spend` (only add the knob if per-transfer
  editing proves tedious).
