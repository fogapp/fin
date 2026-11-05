# Setting up Fin

Fin is installed ([INSTALL.md](INSTALL.md)) and answering on `/up`. This
guide walks from an empty instance to one that is pulling in your accounts,
pricing your holdings, categorising your spending, and telling you when
something needs attention. Do the sections in order the first time; each one
is short.

Everything here is done in the web UI unless noted. Paths like
`/settings#topic=integrations` are the SPA routes: type them into the address
bar or navigate through the sidebar.

---

## 1. Create your account and household

Fin has no passwords. An account is an email plus a **passkey** (Face ID,
Touch ID, Windows Hello, a hardware key, or a password manager that stores
passkeys). Passkeys need HTTPS or `localhost`.

1. Open the app. A fresh instance sends you to `/register`.
2. Enter your email and a display name, then complete the passkey prompt.
3. You land on the dashboard as **admin** of a new household named
   "Your Name's Household". Rename it at `/settings#topic=household`.

On fog, the first **Sign in with fog** on an empty instance registers
instead: fog's operator gets the household and is its admin, and fog decides
who else may sign in. See "Sign in with fog" in
[ACCESS.md](ACCESS.md).

The household is the unit of data. Accounts, transactions, integrations, and
API tokens all belong to a household, and every member sees the same data.

**Then close registration.** Registration is open by default so the first
person can get in. Once you have your account, set
`FIN_OPEN_REGISTRATION=false` in the environment and restart. From then on
new people join only through invite codes (section 10).

**Seeded development instance.** If you ran `bin/rails db:seed`, a household
called "Default" already exists with two years of demo data, a user
`dev@fin.local`, and an API token. That user has no passkey yet. The seed
prints an invite code; open `/register?invite=<code>`, enter
`dev@fin.local`, and enroll a passkey to sign in as that user. Registering
with any other email creates a separate, empty household instead.

**Restoring a backup instead?** A fresh instance's registration page offers a
restore door. See "Backups and restore" in [INSTALL.md](INSTALL.md).

---

## 2. Connect integrations

`/settings#topic=integrations` lists every external provider. Keys are stored
encrypted in the database per household; you never need to put them in the
environment. (The instance does need its `AR_ENCRYPTION_*` keys set to store
them; see [INSTALL.md](INSTALL.md).) Each card has a **Test** button that
makes one real call.

Nothing here is mandatory. Pick what matches the data you have.

| Provider | What it gives you | Get a key at | Free tier notes |
|---|---|---|---|
| **Plaid** | Bank, credit card, and brokerage accounts synced automatically | dashboard.plaid.com | Client ID + secret + environment: `sandbox` for test data, `production` for real accounts. Production needs Plaid's approval |
| **Tiingo** | Daily price history for stocks, ETFs, mutual funds, and crypto. Preferred candle source | tiingo.com | 50 requests/hour, 1,000/day. Fin budgets 45/hour |
| **Alpha Vantage** | Quotes, ticker search, company overviews, news. Fallback candle source | alphavantage.co | 25 requests/day free; Fin budgets 70 per sync run, so a paid tier is worth it if you hold many symbols |
| **CoinMarketCap** | Crypto spot quotes | coinmarketcap.com/api | Free tier is enough |
| **Coinbase** | Coinbase accounts and trades | Coinbase Developer Platform, "Advanced Trade" API key | Key ID + secret |
| **Alchemy** | Self-custody wallet balances and on-chain transactions on Ethereum, Base, Polygon, Arbitrum, Optimism | alchemy.com | API key; plus a Notify auth token and public base URL if you want webhook-driven syncs |
| **RentCast** | Property valuations for real estate | rentcast.io | 50 requests/month. Fin enforces this quota itself; the Test button costs one request |
| **Office** | Fin's tables as spreadsheets in an Office instance, and spreadsheets imported back as transactions | your own Office install (a fog app) | Instance URL + an API token minted in Office |

CoinGecko is used keylessly as a last-resort crypto candle source and needs
no setup.

**Recommended minimum:** Plaid for accounts, Tiingo for prices. Add Alpha
Vantage if you want ticker search and news. Add CoinMarketCap if you hold
crypto.

### How Fin picks a price provider

Each capability has an ordered preference list, and the first *configured*
provider wins:

| Capability | Order |
|---|---|
| Candles (stocks/funds) | Tiingo, then Alpha Vantage |
| Candles (crypto) | Tiingo, then CoinGecko |
| Quotes (stocks) | Alpha Vantage |
| Quotes (crypto) | CoinMarketCap |
| Search, overviews, news | Alpha Vantage |

Adding or removing an integration re-pins every instrument automatically. The
runner-up provider doubles as a daily cross-check: if two sources disagree on
a close by more than 0.5% (2% for crypto), Fin raises an Issue.

### Plaid specifics

- Link accounts from `/accounts` → **New account** → the Plaid option, or from
  the Plaid card in Integrations. Fin asks Plaid for the `transactions` and
  `investments` products.
- Each linked account becomes a Fin account. Checking, savings, credit
  cards, and brokerages are all supported. A Plaid brokerage account brings
  holdings and investment transactions too.
- Sync runs daily at 4:30am, every 6 hours through the seeded "Bank & card
  sync" workflow, and on demand from the account page.
- There is no Plaid webhook receiver. Syncs are poll-based.
- Pending transactions are adopted in place when they settle, so nothing is
  duplicated.

### Alchemy specifics

1. Enter the API key and save.
2. Add wallets: address, label, and the networks to watch.
3. Balances sync every 6 hours. To also track transactions, enable
   **Transactions** on the Alchemy card and pick a sync frequency. First
   enable triggers a full backfill from block zero, which can take a while.
4. For near-real-time updates, add the Notify **auth token** and the
   **public base URL** of your instance. Fin registers one address-activity
   webhook per network at `<base URL>/webhooks/alchemy` and verifies each
   delivery's signature. Webhooks are hints; the poll remains the source of
   truth, so nothing is lost if one is missed.

### Office: spreadsheets from your tables

Office, a self-hosted document editor that runs on fog, can hold any of
Fin's tables as a real spreadsheet. It is mostly a destination rather than a
source, but it connects like any other: **Settings → Integrations → Office**.
On fog, connecting Office's `documents` offer on Fin's Integrations tab does
the same without copying a token.

It asks for two things:

- **Office URL** — where the instance is reachable from Fin, the same
  address you open in a browser.
- **API token** — minted in Office under Settings → API tokens. Name it
  `fin` so you can revoke it on its own.

**Test connection** calls Office and confirms the spreadsheet tools are there.
`OFFICE_URL` and `OFFICE_API_TOKEN` still work as a deployment-wide fallback
for a household that has saved nothing; the settings pane says so when the
connection is coming from the environment.

Once it answers, a spreadsheet button appears beside the CSV download on the
transactions table, on an account's holdings, and on the portfolio. It offers:

- **New spreadsheet** — Fin rebuilds the dataset server-side under the
  table's current filters (including the search box and the transfers toggle),
  and creates it in Office as CSV. The whole filtered set goes, not just the
  rows the page had loaded.
- **The sheets it made before** — picking one rewrites that same Office
  document from A1, so a sheet you have formatted, charted or linked from
  elsewhere keeps its identity and its URL. Rows that have since disappeared
  are blanked rather than left behind.

The Office card lists every linked spreadsheet with its row count, when it was
last refreshed, and why the last refresh failed if it did.

It also works the other way: an account's **Import CSV** dialog has a
**From Office** tab that reads a spreadsheet in the simple layout described
under [Importing CSVs](#importing-csvs) and imports its rows as transactions.

Every call acts as the token's Office user, so Fin's spreadsheets are owned
by whoever minted the token and are private in Office unless you say
otherwise. Removing the connection — or pointing Fin at a different
instance, where the recorded document ids would mean nothing — drops the links
but never touches the spreadsheets themselves.

---

## 3. Accounts and brokers

`/accounts` lists every account. Plaid creates them for you. For anything
else, create them by hand:

1. Add a **broker** (institution) at `/settings#topic=brokers` if it does not
   exist. Brokers group accounts and are where CSV exports come from.
2. Add the **account** at `/accounts` with its type (checking, savings, credit
   card, brokerage, IRA, loan, ...) and last four digits.

Loans and mortgages live at `/loans`. A loan can be linked to a real estate
property so the property's equity is computed rather than double counted.

### Importing CSVs

Fin imports CSV exports from your institutions. Open `/accounts`, pick the
account, and use **Import CSV**. Formats are auto-detected from the header
row:

| Detected when the header has | Treated as |
|---|---|
| `Trade Date` and `Quantity` | Brokerage transactions (buys, sells, dividends, interest, fees) |
| `Trade Date` and `Tran Code` | Checking / bank activity |
| `Asset Class` and `Pricing Date` | Brokerage holdings snapshot |
| `Transaction Date` and `Post Date` | Credit card activity |
| `Date`, `Description`, and `Amount` (or `Debit` and `Credit`) | A hand-kept spreadsheet, in Fin's own simple layout |

The first four match specific institutions' export formats. For anything
else, rearrange the export into the spreadsheet layout: `Date`,
`Description`, and `Amount` are required (negative for money out), and
`Post Date`, `Category`, `Type`, `Memo`, and `Balance` are optional. The
import dialog lists the columns, and an unrecognised header row is answered
with the renames that would fix it.

Imports are idempotent. Every row is hashed, so re-uploading the same file, or
overlapping date ranges, never creates duplicates. Upload monthly exports
without worrying about overlap.

From a shell:

```sh
bin/rails import:csv FILE=path/to/export.csv BROKER="Fidelity"
```

Adding a new institution format means a new importer under
`app/services/importers/` and a detection rule in the dispatcher.

---

## 4. Market data and watchlist

Holdings are priced automatically once a candle provider is configured. The
nightly sync at 5:00am spends each provider's budget in priority order:
instruments you **hold**, then instruments you **watch**, then the benchmark
indices (SPY, QQQ, DIA, IWM). Anything outside those tiers is never fetched.

- Watch a ticker from `/market` → **Add**. Fin searches Alpha Vantage if
  configured, otherwise takes the symbol as typed.
- Each security page at `/market/:id` shows candles, your transactions, news,
  and the provider currently pinned to it.
- `/settings#topic=market` sets which columns the securities list shows.
- Force a refresh from a security page, or run the "Market data sync"
  workflow at `/workflows`.

FX rates sync daily at 5:45am for any account whose currency is not USD.

---

## 5. Categories, merchants, tags

Fin's spending model is a **merchant** with a default **category**, and
**tags** for anything cross-cutting.

- `/categories` — a two-level tree. Create top-level categories
  (Groceries, Dining, ...) and subcategories under them. Reports roll
  subcategories up into their parents.
- `/merchants` — one row per counterparty. Assign each a category, and it
  applies to every transaction from that merchant. Exclude a merchant from
  spending totals at `/settings#topic=merchants` (useful for transfers to
  yourself or reimbursed business spend).
- `/tags` — free-form labels applied per transaction.

New transactions arrive with a raw bank description. Fin matches them to
merchants using the rules you build (next section). Until then they show as
uncategorised. Bulk-assign from `/transactions` using the checkbox toolbar.

Saved filters on `/transactions` are **saved views**; anything you filter to
often is worth saving.

---

## 6. Workflows

`/workflows` is the automation layer. A workflow is a trigger plus a chain of
steps, each with conditions and actions. Two uses dominate:

**Auto-categorisation.** Trigger on `cash_transaction.created`, match the
description (contains, regex, amount ranges, account, ...), then
`assign_merchant`, `assign_category`, `assign_account`, `add_tag`, or
`set_memo`. Use **Preview** to dry-run against existing transactions and
**Apply to existing** to backfill. Every run is logged and can be reverted
from `/workflows/:id/runs`.

**Schedules and alerts.** Your household came with these already active:

| Workflow | What it does |
|---|---|
| Market data sync | Daily 05:00 price fetch |
| Crypto quotes sync | Every 4 hours |
| Security news sync | Daily 06:00 |
| Bank & card sync | Plaid every 6 hours |
| Coinbase sync | Every 4 hours |
| Reconciliation sweep | Daily 03:30, compares ledger positions to broker snapshots |
| System audit | Daily 04:00, raises data-health Issues |
| Subscription detection | Daily 06:30 |
| Monthly review | Notifies when a month's review is ready |
| Charge coming up | Notifies before a known subscription bills |
| Budget alerts | Notifies when a category exceeds its budget |

Edit their wording, thresholds, or schedules freely. The core syncs also run
from `config/recurring.yml` regardless, so archiving a schedule workflow will
not silently stop your bank data.

Other actions available: `mark_as_transfer`, `transfer_to_account`,
`set_loan`, `create_issue`, `trigger_sync`, `run_workflow` (chaining),
`notify`, `webhook` (POST a JSON event to any HTTPS URL), and `fog_event`
("send to HUD": publish to fog's household event stream; see ACCESS.md).

Besides record events and schedules, a workflow can be a **monitor**: a
condition such as a balance threshold or a spend limit, re-checked every 15
minutes, that fires when it becomes true.

`/settings#topic=workflows` sets how verbose the run log is.

---

## 7. Cashflow: budget, subscriptions, transfers

All under `/cashflow`, one section each.

**Budget** (`#section=budget`). Zero-based monthly budget with three line
types: fixed, flex, and non-monthly (accrues toward an annual amount).
Unspent flex rolls over if you enable it per line. **Autofill** proposes
amounts from your last three months. Crossing 90% or 100% of a line fires
`budget.category_approaching` or `budget.category_exceeded`. The seeded
"Budget alerts" workflow turns the second into a notification; add a
workflow on the first if you want an early warning.

**Subscriptions** (`#section=subscriptions`). Fin detects recurring charges
from transaction cadence with no manual tagging. New detections appear as
*proposed*; **Accept** to track them, **Dismiss** to hide. Tracked series
predict the next charge, feed the calendar, and power the "Upcoming charge"
notification. Detection runs nightly, after every import, and after a Plaid
sync that brings new transactions.

**Transfers** (`#section=transfers`). Money moving between your own accounts
(credit card payments, brokerage deposits, savings sweeps) must not count as
spend or income. Fin proposes transfer pairs every 6 hours; **Confirm** or
**Dismiss** them. Confirmed credit card payments are matched automatically
once a pattern is established.

If you imported history before this feature existed, run once:

```sh
bin/rails payments:backfill
bin/rails metrics:backfill_all
```

---

## 8. Investments, real estate, equity, taxes

**Positions** are rebuilt from the investment ledger (buys, sells, dividends,
transfers) and reconciled nightly against broker holdings snapshots. Drift
shows up as an Issue with an **Accept** action that books an adjustment.

**Tax lots** at `/investments` → Cost basis. Generate lots from the ledger,
or create them by hand for positions whose history predates Fin.

**Real estate** (`/investments#section=real_estate`). Add a property by
address. With RentCast configured, Fin fetches a valuation, tax assessment
history, and sale history on create, then refreshes weekly on Mondays within
your monthly quota. Without RentCast, enter valuations manually. Link the
mortgage from `/loans`.

**Equity compensation** (`#section=equity`). Add the company, its FMV history,
and each grant (ISO, NSO, RSU) with its vesting schedule. Fin projects
vesting, computes unrealised value, and can model an exercise plan. Whether
unvested value counts toward net worth is a household toggle.

**Taxes** (`/taxes`). Fill in the tax profile for the year: filing status,
state, projected wages, withholding to date, prior-year figures. Fin then
estimates federal liability from your ledger, and state liability for
California (modelled), states with no wage income tax (zero), or any other
state from the projected state tax you enter. It also tracks quarterly
estimated payments and safe harbour, keeps a document checklist, flags wash
sales, and exports a JSON bundle for your preparer.

---

## 9. Dashboard, stats, notifications

- **Dashboard** (`/`). Click **Customize** to choose widgets from 21
  available: net worth, cashflow, budget pace, upcoming bills, portfolio,
  allocation, performance, dividend income, crypto, real estate, equity
  vesting, data health, and more. Selections are per user.
- **Stats** (`/stats`). Eleven long-run metrics (monthly spend, income,
  savings rate, net worth, portfolio value, ...) recomputed nightly at 6:45am.
  After a big import, `bin/rails metrics:backfill_all` recomputes history.
- **Monthly review** (`/review`). A digest of each closed month, generated on
  the 1st.
- **Notifications** appear in the bell menu. They are in-app only by default.
  To push them somewhere (ntfy, Home Assistant, a relay), set the household's
  notification webhook URL from a console; there is no UI for it yet:

  ```sh
  bin/rails runner 'Household.find_by!(name: "…").update!(notification_webhook_url: "https://ntfy.sh/your-topic")'
  ```

  Every notification then POSTs `{title, body, severity, workflow, event_type}`
  to that URL. On fog, every notification is also published to fog's
  household event stream as `fin.notification` (see ACCESS.md). There is no
  email or mobile push.
- **Issues** (`/settings#topic=issues`). Data-health findings from the nightly
  audit: unpriced holdings, stale syncs, reconciliation drift, provider
  disagreements. Dismiss or act on them; **Run audit** re-checks now.
- **Activity** (`/activity`). Every job, sync, workflow run, and webhook,
  linked by trace ID.

---

## 10. People, devices, tokens

- **Invite someone** at `/settings#topic=household` → Invites. Choose a role
  (`member` or `admin`) and expiry (default 7 days). Send them the link; they
  register a passkey with the code and land in your household. Codes are
  single-use.
- **Add a device** for yourself at `/settings#topic=devices` → Generate device
  link. Open it on the new device within 15 minutes to enroll another passkey.
- **API tokens** at `/settings#topic=tokens` for scripts, the MCP server, and
  other API clients. See [ACCESS.md](ACCESS.md).
- **Backups** at `/settings#topic=backup`: create and download a copy of the
  whole instance, copy the instance keys a restore needs, and make sign-in
  links before moving to a new address. See "Backups and restore" in
  [INSTALL.md](INSTALL.md).
- **Time zone** at `/settings#topic=household` → Time zone. Defaults to
  `America/Los_Angeles`. It is instance-wide, not per household: it decides
  what counts as today and this month, and when the schedule below and
  scheduled workflows run. Any household admin can change it; members see
  it read-only. A changed zone reaches the job worker within a minute; each
  nightly job fires once more at its old time, then follows the new zone
  (restart the worker to apply it at once).
- **Multiple households**: create another from the Household settings and
  switch between them from the account menu. Each has its own data and
  integrations.

Roles: admins manage members, invites, integrations, and household settings.
Members see and edit data. The last admin cannot be removed or demoted.

---

## 11. Things that run on their own

For reference, the built-in schedule in `config/recurring.yml`. Times are
in the instance time zone (Settings → Household → Time zone; default
`America/Los_Angeles`).

| Time | Job |
|---|---|
| 01:00 | Snapshot account balances |
| 02:00 | Prune old activity |
| 04:30 | Plaid sync |
| 05:00 | Market prices |
| 05:40 | Cross-provider price check |
| 05:45 | FX rates |
| 06:00 | System audit |
| 06:15 | Subscription detection; real estate (Mondays) |
| 06:45 | Metrics refresh |
| 07:00 | Equity vest scan |
| 07:15 | Monthly review (1st of month) |
| 07:30 | Tax scan (Mondays) |
| every 4h | Crypto quotes |
| every 5m | Workflow schedule tick, Alchemy transaction tick |
| every 15m | Monitor workflow sweep |
| every 6h | Transfer candidate detection, Coinbase sync, Alchemy balance sync |

All of this needs the worker process running. If the dashboard's data health
widget says syncs are stale, check the worker first.

---

## Checklist

- [ ] Registered with a passkey; household renamed
- [ ] `FIN_OPEN_REGISTRATION=false` set in production
- [ ] Plaid linked, or accounts created and CSVs imported
- [ ] Tiingo (or Alpha Vantage) key entered; holdings show prices
- [ ] Categories and merchants reviewed; a categorisation workflow or two
- [ ] Transfers confirmed so credit card payments are not counted as spend
- [ ] Budget lines set, or autofilled
- [ ] Dashboard widgets chosen
- [ ] Backups configured (see INSTALL.md); encryption keys stored safely
