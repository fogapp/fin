# Fin

**A self-hosted hub for a household's financial life.** Fin pulls your
bank, card, brokerage, crypto, property, and equity-compensation data into
one normalised Postgres database, keeps it current on its own, and gives you
the views a good personal finance app would: cashflow, budget, subscriptions,
net worth, portfolio performance, taxes. Everything stays on your hardware,
and every number can be traced back to the transactions that produced it.

Fin exists because the hosted alternatives each owned one slice of the
picture, changed or shut down on their own schedule, and never let you ask
your own questions of your own data. It is built for one household (a few
people, one or more admins), so it favours clarity and correctness over
multi-tenant scale.

| Document | Read it when |
|---|---|
| [INSTALL.md](INSTALL.md) | You are putting Fin on a machine: Docker Compose, a native toolchain, the production image, or fog. |
| [SETUP.md](SETUP.md) | Fin is running and you want it connected to your accounts and doing useful work. |
| [ACCESS.md](ACCESS.md) | You need to sign in, mint a token, connect an agent over MCP, or wire a webhook. |
| [AGENTS.md](AGENTS.md) | You are changing the code. Architecture, conventions, and the deploy pipeline. |
| [docs/](docs/) | Design notes for the larger subsystems. |

## What Fin does

Data comes in from three directions and lands in one ledger:

```
Plaid (banks, cards, brokerages) ─┐
CSV exports and spreadsheets     ─┼──▶ cash ledger ──▶ merchants / categories / tags ──▶ cashflow, budget, subscriptions
Coinbase, Alchemy wallets        ─┘         │
                                            └──▶ investment ledger ──▶ positions ──▶ portfolio, cost basis, net worth
Tiingo / Alpha Vantage / CoinMarketCap ──▶ price store ─────────────────┘
RentCast ──▶ property valuations ──────────────────────────────────────┘
```

Around that ledger:

- **Workflows.** An event-driven automation engine. Trigger on a record
  change, a schedule, a monitored threshold, or an app event; match with
  conditions; run actions such as
  assign category, tag, mark as transfer, notify, call a webhook, or kick off
  a sync. Every run is logged, previewable, and revertible.
- **Detection.** Recurring charges are found from cadence, not tagging.
  Transfers between your own accounts, including credit card payments, are
  proposed and confirmed so they never count as spend. Ledger positions are
  reconciled nightly against broker holdings and drift becomes an Issue.
- **Market data.** Instruments are resolved to a stable identity, priced from
  a preferred provider with automatic fallback and a daily cross-provider
  integrity check, within each provider's rate budget.
- **Health.** A nightly audit raises Issues for stale syncs, unpriced
  holdings, and inconsistent data. An Activity trail links every job,
  workflow run, and webhook by trace ID.

## The console

| Page | What it is for |
|---|---|
| **Dashboard** | Configurable widgets: net worth, cashflow now, budget pace, upcoming bills, portfolio, allocation, performance, crypto, real estate, vesting, data health. |
| **Transactions** | The full cash ledger with filters, saved views, bulk edits, and a detail page per transaction. |
| **Cashflow** | Income vs spend over time, category and merchant breakdowns, Sankey flows, budget, subscriptions, transfers, and the monthly review. |
| **Investments** | Positions, performance (time-weighted and money-weighted), cost basis and tax lots, real estate, equity grants, and the investment ledger. |
| **Market** | Watchlist and per-security pages with candles, news, holdings, and provider status. |
| **Accounts / Loans** | Balances, history, holdings, CSV import, and linked mortgages. |
| **Merchants / Categories / Tags** | The classification model with spend charts and drill-down. |
| **Workflows** | The automation builder, run history, and reverts. |
| **Taxes** | Estimated liability, quarterly payments, safe harbour, checklist, wash sales, export. |
| **Stats** | Long-run metrics with history. |
| **Settings** | Household and members, devices, integrations, API tokens, issues, defaults, appearance. |

Sitewide search is one keystroke away (Cmd/Ctrl+K).

## Other ways in

- **API.** Everything the console does is JSON under `/api/v1`, bearer
  authenticated, documented at `/api-docs`.
- **MCP.** Agents connect to `/mcp` with an API token and get read-only tools
  for accounts, transactions, net worth, cashflow, budget, and the dashboard.
- **Webhooks.** Alchemy pushes wallet activity in; workflows and
  notifications push JSON events out.
- **Backups.** A fog-backup/2 producer and restore-on-boot, so a fog-managed
  host can snapshot and rebuild the instance. The same artifact downloads
  from Settings → Backup and restores into a fresh instance, at the same
  address or a new one.

## Stack

Rails 8.1 on Ruby 4.0 (JSON API, Sorbet-typed), Postgres 18 with Solid Queue
and Solid Cache in the same database, a React 19 + TypeScript + Vite +
Tailwind v4 console. One Docker image runs the web process and the worker.
In production it runs as an app on [fog](https://github.com/fogapp/fog), a
self-hosting platform, and the same image runs anywhere with a Postgres 18.

## Development at a glance

```sh
cp .env.example .env
docker compose up --build                     # db, web (:3001), worker, vite (:5173)
docker compose exec web bin/rails db:seed     # prints the demo invite + API token
```

Open http://localhost:5173, register with the printed invite, and explore
two years of synthetic data. Full instructions in [INSTALL.md](INSTALL.md);
conventions in [AGENTS.md](AGENTS.md).

Before committing: `bundle exec rspec`, `bin/rubocop`, `bin/brakeman`,
`bin/bundler-audit`, and in `frontend/` `npm test`, `npm run lint`,
`npm run build`.

## License

Fin is free software under the GNU Affero General Public License v3.0 (AGPL-3.0-only); see [LICENSE](LICENSE). The bundled fonts are under the SIL Open Font License; see `public/fonts/OFL.txt`.
