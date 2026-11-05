# Subscriptions Redesign — Recurring Series

**Status:** Implemented 2026-07-13 (`recurring_series` / `recurring_occurrences`,
`app/services/recurring/**`). Section 1 describes the `RecurringPattern` system this
replaced, which no longer exists. As built, grouping lives in `Recurring::Normalizer` /
`Recurring::Detector` and backtest scoring in `Recurring::CadenceDetector`, rather than
separate `Grouper` / `Backtester` classes.

Design for replacing the current `RecurringPattern` system with a full subscription
lifecycle: detection → review → accepted tracking → monitoring. Informed by an audit
of the current implementation and research into Plaid Recurring Transactions, Monarch,
Lunch Money, Copilot, Rocket Money, Actual Budget, Sure, and the Capital One/Yodlee
detection patents.

## 1. What exists today, and why it falls short

The current system is a single job (`DetectRecurringPatternsJob`) that upserts
`recurring_patterns` rows keyed on `(merchant_id, description)`. The UI
(`SubscriptionsSection` on the Cashflow page) is read-only.

Problems:

- **No user lifecycle.** Everything the detector finds is displayed. There is no
  accept, dismiss, or remove — false positives sit on the page forever, and there is
  no way to say "this one is real."
- **No evidence.** `RecurringPattern` has no link to its transactions
  (`transaction_count` is a denormalized integer). You cannot see the history that
  produced a suggestion, so you can't judge whether it's correct.
- **Weak cadence model.** One coverage heuristic per bucket (weekly/monthly/
  quarterly/annual), a fixed 30/91/365-day interval, no biweekly, no day-of-month
  anchor, no month-end or Nth-weekday handling. `MIN_OCCURRENCES = 2` is below the
  industry floor of 3 and produces noisy suggestions.
- **Hard amount cutoff.** A single >20%-deviation rejects the whole group, so
  variable bills (utilities) can never be detected, and one refund or promo price
  poisons an otherwise clean series.
- **No monitoring.** No missed-payment state beyond a binary `overdue`, no
  price-change detection, no forecast of upcoming charges.

## 2. Design overview

Three layers, mirroring what the best products converge on:

1. **Detection** — a rewritten engine that groups transactions per merchant,
   hypothesizes candidate cadences, verifies them against history
   (Actual Budget's hypothesize-and-verify pattern), and emits **suggested**
   series with full transaction evidence.
2. **Review** — a queue where each suggestion shows its matched history timeline;
   the user **accepts** (→ active) or **dismisses** (suppressed permanently, but
   reversible).
3. **Tracking** — accepted series become the primary content of the Subscriptions
   page. Each owns matching criteria that attach *future* transactions as they sync,
   an occurrence timeline (paid / due / missed / price-changed), a predicted next
   date, and workflow events for price hikes and missed payments. Users can edit,
   end, or delete a series at any time.

The core inversion vs. today: **detection proposes once; the user's decision is
durable.** The detector never overwrites or resurfaces something the user has acted
on. After acceptance, the series is maintained by *matching* (attaching new
transactions to an expected schedule), not by re-derivation.

## 3. Data model

Two new tables replace `recurring_patterns`.

### `recurring_series`

The stream entity (Plaid `TransactionStream` / Lunch Money Recurring Item analog).
Household-scoped (`HouseholdScoped`), UUID PK.

| Column | Type | Notes |
|---|---|---|
| `status` | string | `suggested`, `active`, `dismissed`, `lapsed`, `ended` |
| `source` | string | `detected`, `manual` |
| `merchant_id` | uuid, nullable | canonical merchant when resolved |
| `description_pattern` | string, nullable | normalized-description fallback key + match criterion |
| `account_id` | uuid, nullable | reserved; detection groups household-wide (see §4.1) so a subscription that moves between cards keeps one stream |
| `name` | string | display name, user-editable (defaults to merchant/description) |
| `kind` | string | `subscription` (fixed price), `bill` (variable), inferred from amount CV, user-editable |
| `granularity` | string | `week`, `month`, `year` |
| `quantity` | integer | every N granularities — biweekly = week/2, quarterly = month/3 |
| `anchor` | jsonb | cadence anchor: `{day_of_month: 15}`, `{day_of_month: "last"}`, `{weekday: 5}`, `{nth_weekday: [3, 5]}`, `{month: 11, day: 3}` for annual |
| `average_amount` / `last_amount` / `min_amount` / `max_amount` | decimal | dual representation per Plaid/Ntropy |
| `amount_tolerance` | decimal | fractional band for matching; default 0.075, auto-widened for `bill` kind, user-editable |
| `confidence` | float | backtest score (§5) |
| `first_charge_date` / `last_charge_date` / `next_expected_date` | date | |
| `occurrences_count` | integer | counter cache |
| `misses_streak` | integer | consecutive missed occurrences |
| `accepted_at` / `dismissed_at` / `ended_at` | datetime | lifecycle audit |
| `notes` | text | user notes ("cancel before March", etc.) |

Unique partial index on `(merchant_id, account_id)` and `(description_pattern,
account_id)` where `status != 'ended'` — same upsert-key idea as today, but the
dismissal suppression falls out of it naturally: the detector `find_or_initialize`s
by key, sees `dismissed`, and leaves it alone.

Includes `EmitsWorkflowEvents` and registers in `Workflows::Catalog` (replacing the
`RecurringPattern` registration) with condition fields: `status`, `kind`,
`granularity`, `average_amount`, `confidence`, `misses_streak`.

### `recurring_occurrences`

The evidence + forecast + monitoring table (Lunch Money's occurrence map made
first-class). One row per expected or observed charge.

| Column | Type | Notes |
|---|---|---|
| `recurring_series_id` | uuid | |
| `expected_date` | date | from the schedule; equals `charged_date` for backfilled history |
| `status` | string | `paid`, `paid_amount_changed`, `upcoming`, `due`, `missed`, `skipped` |
| `cash_transaction_id` | uuid, nullable | the matched transaction (null for upcoming/missed) |
| `charged_date` | date, nullable | actual transaction date |
| `amount` | decimal, nullable | actual amount |
| `expected_amount` | decimal | trailing average at prediction time |

Unique on `(recurring_series_id, expected_date)`; index on `cash_transaction_id`
(a transaction belongs to at most one occurrence). `skipped` is a user action
("this month was a one-off, don't count it as missed").

This one table powers: the history timeline in the detail view, missed-payment
detection, price-change detection, the upcoming forecast, and "paid vs. left to pay
this month."

`recurring_patterns` is dropped at the end of the migration (§9).

## 4. Detection engine

New service namespace `app/services/recurring/`, replacing the logic inside the job
(the job shell remains the entry point, still enqueued from `PlaidSyncer` and CSV
imports).

### 4.1 Grouping — `Recurring::Grouper`

Same scope as today (`CashTransaction`, outflows, excluding `Payment` type), plus two
new exclusions: transactions already attached to a reviewed series' occurrence, and
linked transfer legs (same structural rule as `spend_like` — excluded unless the
transfer opts into spend). Group household-wide by merchant when resolved, else by
normalized description — deliberately NOT per-account (Plaid's model), so a
subscription that moves to a reissued card keeps one continuous stream.
Upgrade `normalize_description` to also strip
processor prefixes (`SQ *`, `TST*`, `PAYPAL *`, `PP*`), dates, and trailing
city/state tokens. **Sub-split groups by amount cluster** (Plaid includes amount in
the stream key): if a merchant has two stable price points (e.g. two different
streaming plans on one Amazon account), it yields two candidate series.

### 4.2 Cadence — `Recurring::CadenceDetector` (hypothesize-and-verify)

For each group with ≥ 3 transactions (≥ 2 if the gap is ~365d — annual gets the
industry-standard relaxation):

1. Generate candidate schedules from the observed dates: weekly on weekday W;
   every-2-weeks on weekday W; monthly on day D (D ≤ 28); monthly on last day;
   Nth-weekday-of-month; every-2/3/6-months on day D; yearly on month/day.
2. For each candidate, materialize expected dates across the observed span and score:
   an observed transaction matches an expected date within tolerance
   (**±2 days weekly/biweekly, ±4 days monthly+, ±14 days annual**, with
   weekend-shift awareness) and amount within tolerance (§4.3). Score by hit rate and
   date proximity (`1/(day_diff+1)` per hit, Actual Budget's ranking).
3. Best candidate wins if hit rate ≥ 80% of expected dates and ≥ 3 hits (2 annual).
   This natively handles the cases the current coverage heuristic can't: month-end
   billing, "first Monday," biweekly vs. monthly ambiguity.

### 4.3 Amount — tolerance bands, not hard rejection

Compute mean/CV of amounts. `CV ≤ 0.075` → `kind: subscription`, tolerance 7.5%
(Actual Budget's number). `0.075 < CV ≤ 0.35` → `kind: bill`, tolerance =
`max(0.15, 1.5 × CV)` capped at 35%. Outlier transactions (a refund, a
double-charge) are excluded from the series rather than killing it.

### 4.4 Confidence — backtest scoring

The most reusable idea from the Capital One patent: temporally split each group,
fit the schedule on the first ~70% of occurrences, and score by how well it predicts
the holdout (fraction of predicted dates with a matching transaction, penalized by
amount deviation). A series that genuinely predicts the future scores near 1.0;
coincidental clusters score low. Display as high/medium/low in the UI rather than a
raw float.

### 4.5 Emission

For each surviving candidate: `find_or_initialize` the series by key.
- No series → create as `suggested`, backfill `recurring_occurrences` from the
  matched history (status `paid`), emit `subscription.suggested` workflow event.
- `suggested` → refresh stats/evidence in place.
- `dismissed` / `ended` → do nothing (durable user decision).
- `active` / `lapsed` → do nothing; those are maintained by the Matcher (§6).

## 5. Lifecycle

```
                    accept                       2 consecutive misses
   suggested ───────────────────▶ active ─────────────────────────────▶ lapsed
      │                            │  ▲                                   │
      │ dismiss                    │  └── matching charge reappears ──────┘
      ▼                            │ end (user: "I cancelled this")
   dismissed ◀── (re-dismiss) ─────┴──▶ ended
```

- **suggested** — detector output awaiting review. Shown only in the review queue.
- **active** — user-accepted (or manually created). The primary Subscriptions list.
- **dismissed** — "not a subscription." Hidden everywhere except a "Dismissed"
  management view; never re-suggested. Reversible (restore → suggested).
- **lapsed** — auto: two consecutive `missed` occurrences (Yodlee's rule). Shown in
  an "Inactive" section — this is Rocket Money's "forgotten subscriptions" surface,
  and it's also the *confirmation* view after you cancel something. A new matching
  charge reactivates it.
- **ended** — user removal of an accepted subscription ("I cancelled Netflix").
  History and occurrences are preserved for reporting; matching stops. Distinct from
  hard `destroy`, which is also available and cascades occurrences.

One missed occurrence past grace ⇒ the occurrence is `missed` and the series is
flagged **at risk** (derived: `misses_streak == 1`) — surfaced as a badge, not a
status change.

## 6. Matching — keeping accepted series current

`Recurring::Matcher` runs after every sync/import, *before* the detector, so
matched transactions are excluded from re-detection.

For each `active`/`suggested`/`lapsed` series: find new transactions where merchant
(or description pattern) matches, amount within `amount_tolerance`, and date within
the cadence tolerance of an unfilled expected occurrence.

- Match within amount tolerance → occurrence `paid`.
- Match outside amount tolerance but same merchant near the expected date →
  `paid_amount_changed`, and price-change evaluation fires (§7).
- Roll the schedule: create the next `upcoming` occurrence, update
  `next_expected_date`, `last_amount`, trailing `average_amount`.

A nightly monitor (`config/recurring.yml`, complementing the sync-triggered path)
advances occurrence states by time: `upcoming` → `due` (within 3 days) → `missed`
(past expected + grace), increments `misses_streak`, lapses series at 2, and
tombstones stale suggestions (a `suggested` series whose next expected date passed
unmatched gets confidence-downgraded; two misses delete the suggestion — Plaid's
EARLY_DETECTION tombstoning).

Manual controls on the series: **attach/detach** a specific transaction (Copilot's
pattern) — detach converts the occurrence back to `missed`/`upcoming`; attach fills
it. Matching criteria (amount band, date window, merchant/description) are visible
and editable per series, so the user can see and fix *why* things match.

## 7. Monitoring & workflow events

New app events registered in `Workflows::Catalog` (the model events come free via
`EmitsWorkflowEvents`):

- `subscription.suggested` — new suggestion entered the queue.
- `subscription.price_changed` — Yodlee's dual threshold: fires only when
  `|last − previous| ≥ $10` **and** `≥ 10%`, throttled to once per 31 days per
  series. Payload: old/new amount, deltas.
- `subscription.payment_missed` — occurrence flipped to `missed`.
- `subscription.lapsed` — series auto-deactivated after 2 misses.

These plug into the existing workflow engine for notifications, and the thresholds
become workflow condition fields rather than hard-coded alert rules.

## 8. API & UI

### API (`/api/v1`)

```
GET    /subscriptions                     ?status=active|suggested|lapsed|dismissed|ended
GET    /subscriptions/:id                 series + occurrence timeline + matched transactions
POST   /subscriptions                     manual create (typically from a transaction)
PATCH  /subscriptions/:id                 edit name/kind/cadence/anchor/amount tolerance/notes
POST   /subscriptions/:id/accept          suggested → active
POST   /subscriptions/:id/dismiss         → dismissed
POST   /subscriptions/:id/restore         dismissed/ended → suggested/active
POST   /subscriptions/:id/end             active → ended
DELETE /subscriptions/:id                 hard delete
POST   /subscriptions/:id/occurrences/:occ/attach    {cash_transaction_id}
POST   /subscriptions/:id/occurrences/:occ/detach
POST   /subscriptions/:id/occurrences/:occ/skip
GET    /subscriptions/upcoming            next-30-days forecast across active series
```

Existing `GET /cashflow/subscriptions` is replaced by `GET /subscriptions?status=active`
(one release of aliasing during the frontend cutover, then removed).

### UI

Promote Subscriptions to a **dedicated page** (`/subscriptions` route in the React
app, keeping a link from Cashflow), structured as:

1. **Header stats** — monthly total, annual total, active count, paid vs. left-to-pay
   this month (from occurrences).
2. **Review banner** — "N suggestions to review" with a badge (Monarch's pattern);
   expands into the review queue. Each suggestion card shows name, inferred cadence in
   words ("Monthly on the 15th"), average amount with `~` when variable, confidence
   chip, a **mini occurrence timeline** (last ~8 expected dates as dots:
   hit/miss/amount-changed), and Accept / Dismiss buttons. Batch accept/dismiss via
   checkboxes (Actual Budget's discover modal).
3. **Upcoming strip** — next 14 days of expected charges with dates and amounts.
4. **Active list** — the primary table, grouped by cadence as today, with columns:
   name, amount (± band for bills), /month equivalent, last charge, next expected,
   status badge (at-risk / price-changed). Row click opens the detail pane.
5. **Inactive section** — `lapsed` series ("no charge since …"), with End / Restore.
6. **Detail pane** (reusing the transaction-detail-pane interaction pattern):
   - **History timeline**: every occurrence — expected date, actual date, amount,
     Δ vs. expected, status glyph (green check / yellow check for amount change /
     red X for missed / gray for skipped). This is the "is it correct?" evidence view,
     for both suggestions and accepted series.
   - **Amount sparkline** across occurrences — price history at a glance.
   - **Matching criteria** editor: merchant/description, amount band, cadence + anchor.
   - Actions: accept/dismiss (suggested), end/delete (active), skip occurrence,
     attach/detach transaction, edit, notes.
7. **Transactions page integration**: matched transactions get a recurring badge
   (Copilot's `[R]`); the transaction detail pane links to its series; a transaction
   row action "Mark as recurring…" creates a manual series pre-filled from that
   transaction and its history.
8. **Dismissed management view** — behind a filter, so a wrong dismissal is fixable.

## 9. Migration & rollout

Phased, each phase shippable and spec-covered:

1. **Schema + models** — `recurring_series`, `recurring_occurrences`, model specs,
   factories. `RecurringPattern` untouched.
2. **Detection engine** — `Recurring::Grouper` / `CadenceDetector` / `Backtester`
   writing series+occurrences. Port the existing job spec scenarios (Netflix monthly,
   weekly, annual, payment exclusion, upsert idempotence) plus new ones: biweekly,
   month-end, variable bill, amount-outlier resilience, dismissal suppression,
   annual-with-2-points.
3. **Matcher + lifecycle monitor** — sync-time attachment, nightly state advancement,
   `recurring.yml` entry.
4. **API** — controller, serializers, request + swagger specs.
5. **Frontend** — page, review queue, detail pane, transaction badge.
6. **Workflow events** — catalog registration, price-change/missed-payment emitters;
   convert the `RecurringPattern` catalog entry.
7. **Cutover** — data migration seeds `recurring_series` from live detection
   (everything starts as `suggested`; the first visit to the page is one review
   session over ~the same list the old page showed). Drop `recurring_patterns`,
   delete the old job/controller/section, run the prod backfill.

## 10. Explicitly out of scope (for now)

- Cancellation rails (Rocket Money concierge / Visa Subscription Manager) — no
  consumer API access.
- Cross-user merchant priors — single-household app; the backtest confidence
  substitutes.
- Free-trial-to-paid stream linking — documented nowhere in the industry; revisit.
- Inflow/income streams (payroll) — the schema supports it later (drop the
  `amount < 0` scope and add `direction`), but this redesign targets spend.
