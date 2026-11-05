# Transfers Redesign — One-Sided Transfers, External Accounts, and Learned Recognition

**Date:** 2026-07-06 · **Status:** Implemented 2026-07-06 (phases 1–5; §F "Phase 2" items remain deferred).
Key entry points: `LinkTransferModal.tsx` / `AccountCombobox.tsx` (frontend),
`app/services/workflows/actions/transfer_to_account.rb` (workflow action),
migration `20260706000001_add_account_kind_and_transfer_counterparty.rb`.
The old `RulesEngine::*` namespace referenced below has since been folded into
`Workflows::*` (`Workflows::ActionExecutor`, `Workflows::Actions`, `Conditions::Registry`).
Note: like `mark_as_transfer`, the new action has no workflow-undo delta
(`confirm!` writes via `update_all`, invisible to `change_delta`) — fix both together if undo is ever needed.

## The problems (as stated)

1. Excluding a single transaction from spending because "I know it's a transfer" requires
   matching it against a counterpart transaction. That counterpart isn't always available —
   either the destination account isn't in the system at all, or its transaction feed
   doesn't produce a matchable row.
2. Transfers to accounts outside the system (e.g. an unlinked Schwab account) have no
   representation. "This was a transfer to my Schwab account" should create/find that
   account and learn to recognize future transfers to it.
3. Setting up ongoing recognition should be as easy as merchant tagging: a "Link as
   transfer" action that creates a workflow keyed to the transaction's pattern, the way
   QuickAutomationModal does for merchants — without requiring a matched pair.

## What we have today (verified against the code)

- **Pair entity:** `Transfer` (`db/schema.rb:846-860`) with polymorphic from/to sides and a
  denormalized `transfer_id` back-pointer on both transaction tables. Detection
  (`TransferCandidateService`) matches inverted amounts (±$0.01) across different accounts
  within ±3 days; `DetectTransferCandidatesJob` persists unconfirmed candidates.
- **Exclusion is a single flag check:** `income_like`/`spend_like` scopes
  (`app/models/cash_transaction.rb:50-63`) filter `WHERE transfer_id IS NULL`, and cashflow,
  budgets, and dashboard all consume those scopes. *Anything* that sets `transfer_id`
  is excluded everywhere, pair or no pair.
- **Critically, the model already permits one-sided transfers** — `at_least_one_side`
  (`app/models/transfer.rb:74-78`) only requires one of from/to. No code path creates one
  today, but the exclusion machinery would honor it as-is.
- **The UI requires a pair:** TransactionDrawer's `TransferPicker` must POST both
  `from_transaction_id` and `to_transaction_id`; there is no one-sided path and no
  per-transaction exclusion (only merchant-level exclude).
- **The workflow engine is most of the way there:** `mark_as_transfer` already exists as a
  zero-param data action (`rules_engine/actions/mark_as_transfer.rb`) but *skips* unless it
  finds exactly one counterpart; `assign_account` shows the account-param pattern; and
  QuickAutomationModal already implements "learn from this transaction" (conditions
  prefilled from description/source, live match preview, apply-to-existing).
- **No external-account concept:** `Account` requires a name, an `account_number`, and a
  `Broker`. "Manual" is implicit (no `plaid_accounts` row); there is no `kind`.

## What the industry does (research summary)

Full report available in session research; key findings:

- **Two orthogonal concepts, keep both:** (a) *is this movement internal/neutral?* and
  (b) *are the two legs linked?* The strongest designs (Simplifi, Actual Budget) support a
  hard-linked pair when both sides are tracked **and** a neutral one-sided designation when
  they aren't. Category-only systems (Monarch) leak; pair-only systems (strict YNAB) can't
  express external transfers. Fin has (b); this proposal adds (a) without giving up (b).
- **Represent the untracked side explicitly.** YNAB tracking accounts, Actual off-budget
  accounts, Lunch Money manual assets: the consensus answer to "the other side isn't
  tracked" is a lightweight account object, not a bare flag and never hiding the row.
- **Learning is description-keyed and offered at mark time.** Copilot's benchmark UX: mark
  one transaction as a transfer → immediately offer a name-match rule → allow "just this
  one." YNAB learns from payee strings; Actual routes transfer payees through its general
  rules engine. This maps 1:1 onto Fin's QuickAutomationModal.
- **Exclude but don't hide:** Simplifi grays transfers out in reports rather than omitting
  them; Lunch Money shows grouped pairs as one net-zero row. Excluded money should stay
  auditable.
- **The known failure mode** (Monarch's Zelle problem): transfer-*shaped* transactions that
  are actually payments to other people get silently excluded from spending. Mitigation:
  transfer status commits only via matched counterpart or explicit user action naming
  *their own* account, and candidates surface for review rather than auto-excluding.
- Plaid's PFC taxonomy (TRANSFER_IN/TRANSFER_OUT primaries, LOAN_PAYMENTS_CREDIT_CARD_PAYMENT
  on both CC-payment legs) is a candidate *signal* for detection, never truth.

## Proposed design

### A. External accounts (new account kind)

Add `accounts.kind` — `"standard"` (default) | `"external"`:

- **External accounts** represent real accounts you own that the system doesn't sync:
  created with just a name ("Schwab"). `broker_id` becomes nullable for `kind=external`
  (or they attach to an auto-created per-household "External" broker if we prefer zero
  schema loosening); `account_number` auto-generated (`ext-<short-uuid>`) to satisfy the
  uniqueness constraint. No balance, no sync; excluded from net worth (no balance data);
  hidden from most account lists except transfer pickers and an "External accounts"
  settings group.
- Making the kind explicit also retires the implicit "manual = no plaid row" convention,
  which the API audit already flagged as tech debt.

### B. One-sided transfers with a counterparty account

Add `transfers.counterparty_account_id` (uuid, nullable, FK accounts):

- A one-sided transfer = exactly one transaction side + `counterparty_account_id` set.
  Validation: counterparty is required when only one side is present, and must be absent
  when both sides are present. Direction is inferred from the present side's sign
  (negative → transfer *to* the counterparty; positive → *from*).
- Confirming it sets `transfer_id` on the one real transaction → **spending/income/budget
  exclusion works with zero reporting changes** (the scopes already key off `transfer_id`).
- The counterparty can be an *external* account ("to my Schwab") **or a standard tracked
  account** whose feed simply didn't produce a matchable counterpart (CSV gaps) — same
  mechanism covers both.
- Serializer gains `counterparty_account_id`/`counterparty_account_name`; TransfersSection
  renders one-sided rows as `Checking → Schwab (external)`.

### C. "Link as transfer" without a pair (drawer UX)

`TransferPicker` becomes two paths:

1. **"Match a transaction"** — the existing counterpart search, unchanged (still the best
   outcome when a pair exists).
2. **"To/from an account…"** — an account combobox listing standard + external accounts,
   with inline **"Create external account '⟨typed name⟩'"** (same create-in-combobox
   pattern MerchantCombobox already uses). Picking one POSTs
   `/transfers { from_transaction_id, counterparty_account_id, auto_confirm: true }`.

After a one-sided link succeeds, offer the Copilot-style follow-up inline:
**"Always link ⟨description⟩ to Schwab →"** which opens QuickAutomationModal prefilled
with the transaction's conditions and a `transfer_to_account` action (below) — identical
to the merchant "Create automation" flow, including match preview and apply-to-existing.

Guardrail copy (the Zelle problem): the account path is labeled "Transfer to one of *your*
accounts"; payments to other people should stay categorized spending. We never auto-commit
transfer status from description shape alone.

### D. New workflow action: `transfer_to_account { account_id }`

The precise, parameterized sibling of the existing `mark_as_transfer`:

- **Behavior:** skip if `transfer_id` already set. Try the standard counterpart match
  *restricted to the target account* (inverted amount, ±3 days) — if exactly one match,
  create a confirmed **pair** (best case). Otherwise create a confirmed **one-sided**
  transfer with `counterparty_account_id = account_id`. If a later-synced counterpart shows
  up, detection can upgrade the one-sided record (phase 2, below).
- **Registration surface** (all verified): `RulesEngine::ActionExecutor::ACTION_CLASSES` +
  `PARAM_BUILDERS` (account_id pass-through, like `assign_account`),
  `Workflows::Actions::DATA_ACTIONS`, `RulesEngine::Registry` actions for CashTransaction,
  a new action class modeled on `mark_as_transfer.rb`, and an ActionParamsForm case in the
  builder UI (reuse the existing `assign_account` account Select). Undo delta: record the
  created transfer id; revert destroys it (which auto-unlinks via `before_destroy`).
- Existing `mark_as_transfer` stays as the generic "pair with any unique counterpart"
  action; `transfer_to_account` supersedes it for account-specific recognition.

### E. Reporting: exclude but don't hide

- Exclusion semantics unchanged (`transfer_id IS NULL` in `income_like`/`spend_like`).
- Add a small **Transfer badge** on rows in TransactionTable when "Show transfers" is on
  (today linked rows are indistinguishable); the badge names the counterparty
  ("→ Schwab") when known.
- Hygiene fix found during review: cashflow's top-categories/merchants drill-downs filter
  on `transaction_type = 'Sale'` directly and skip the `transfer_id` guard
  (`app/domain/api/render/cashflow.rb:35-70`). Add the guard so a transfer marked on a
  credit-card transaction can't leak into drill-downs.
- Optional (phase 2): a "Transfers" line in cashflow so movement is auditable —
  net-zero for internal pairs, listed for boundary (external) transfers.

### F. Phase 2 (explicitly deferred)

- **Upgrade one-sided → pair:** when a counterpart transaction later appears (account gets
  synced, CSV import backfills), detection matches it against open one-sided transfers on
  the same account/amount/window and merges.
- **Merge external → synced account:** when the user links the real Schwab via Plaid, offer
  to fold the external account into it (reassign `counterparty_account_id`, rerun matching).
- **Plaid PFC signal:** use TRANSFER_IN/OUT + `LOAN_PAYMENTS_CREDIT_CARD_PAYMENT` detailed
  categories to boost candidate detection confidence (proposal-only, never auto-commit).
- Cashflow "Transfers" bucket; per-side re-include toggle (Simplifi-style) if ever needed.

## Implementation order

1. **Migration + model** — `accounts.kind`, `transfers.counterparty_account_id`, transfer
   validations (one-side ⇔ counterparty), Account external-create path. (small)
2. **API** — transfers#create accepts `counterparty_account_id`; serializers; external
   account create endpoint (reuse accounts#create with kind). (small)
3. **Workflow action** — `transfer_to_account` class + 4 registration points + undo +
   ActionParamsForm editor + catalog test. (medium)
4. **Drawer UX** — two-path TransferPicker, external-account inline create, post-link
   "always do this" handoff to QuickAutomationModal (add the action type to its payload
   builder). (largest piece)
5. **TransfersSection + table badge + drill-down guard.** (small)

Everything rides the existing exclusion flag, so no budget/cashflow/dashboard math changes
and no data backfill are required. The design deliberately keeps pairs as the preferred
representation — one-sided is the fallback, and the workflow action always tries to pair
first.
