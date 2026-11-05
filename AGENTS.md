# AGENTS.md

Fin — a self-hosted personal finance hub: investment portfolios, bank/credit-card
transactions, merchants/categories/tags, CSV + Plaid imports, workflows, and market-data sync.
Built for one household (a few people), so favor clarity and correctness over
multi-tenant scaling concerns.

## Architecture

Two-part app: a **Rails API** backend and a **React SPA** frontend that talks to it over `/api`.

- **Backend** — Rails 8.1 / Ruby 4.0.9 / Postgres 18.
  - Sorbet-typed (`sorbet-runtime`, `tapioca`); keep sigs valid.
  - Solid Queue for background jobs (`bin/jobs`, worker process).
  - JSON API under `app/controllers/api/v1/**`; `spa_controller.rb` serves the built SPA.
  - API documented with rswag/Swagger at `/api-docs`.
  - Auth: passkeys / WebAuthn, optional OpenID Connect sign-in ("Sign in with fog"), and
    bearer API tokens (`app/controllers/concerns/api_token_authentication.rb`). MCP server at `/mcp`.
  - Integrations: Plaid (banks, cards, brokerages); Tiingo, Alpha Vantage, CoinMarketCap and
    CoinGecko (market data); Coinbase and Alchemy (crypto); RentCast (property values); Office
    (spreadsheets). Credentials are stored per household, encrypted with Active Record Encryption.
- **Frontend** — `frontend/`: React 19 + TypeScript + Vite + Tailwind CSS v4 + Radix.
  - Vite dev server proxies `/api`, `/api-docs` and `/auth/oidc` to the backend (`API_TARGET`,
    default `http://localhost:3001`).
  - **Design: read [`frontend/DESIGN.md`](frontend/DESIGN.md) before touching UI.**
    `frontend/CLAUDE.md` carries the non-negotiable rules (semantic color tokens only,
    theme structure, component conventions). This is the source of truth for visual
    consistency across the app's themes.

## Key patterns

- **Idempotent imports** via `source_row_hash` (re-importing a file never duplicates rows).
- **Importer dispatcher** — `app/services/importers/dispatcher.rb` routes CSVs to
  format-specific importers (`broker_csv`, `checking_csv`, `credit_card_csv`, `holdings_csv`,
  `spreadsheet_csv`), which share the `RowImport` scaffolding.
- **Unified cash ledger** — bank and credit-card activity share one `cash_transaction` model,
  told apart by its source.
- **Workflows** — the event-driven automation engine (`app/services/workflows/**`,
  `workflow` / `workflow_step` / `workflow_run`): match conditions → actions, with chaining,
  cycle detection, dry-run preview, undo, and an audit log. `merchant_rule` is separate and
  narrower — a description regex → merchant mapping that importers and Plaid sync apply
  (`Merchants::RuleMatcher`).
- **Where logic lives** — business logic is in `app/services/**` (one directory per subsystem) and
  `app/jobs/**`, not in controllers. `app/domain/**` holds the API response renderers
  (`Api::Render::*`), the response cache, and the MCP tools.
- **Households** — every household-owned model includes `HouseholdScoped`; the API token sets
  `Current.household`, so queries are scoped without a household parameter.
- **Job queues** — `config/queue.yml` lists every queue explicitly. A job on a queue not listed
  there never runs, so a new `queue_as` needs an entry.

## Running locally

```bash
cp .env.example .env               # optional keys; see INSTALL.md, "The .env file"
docker compose up --build          # db, web (Rails), worker, frontend (Vite)
docker compose exec web bin/rails db:seed   # prints the demo invite code and API token
```

Open **http://localhost:5173** (Vite), go to `/register?invite=<code>` with `dev@fin.local`,
and enroll a passkey. The API token (`dev-token-fin-local`) is for API and MCP calls.
The Rails API is exposed on **http://localhost:3001**. Native setup is in INSTALL.md.

## Checks before committing

- Backend: `bundle exec rspec`, `bin/rubocop`, `bin/brakeman`, `bin/bundler-audit`.
- Frontend (in `frontend/`): `npm test`, `npm run lint`, `npm run build`, and the design guard
  grep in `frontend/CLAUDE.md` (no raw palette colors in UI).
- API shape changed? The swagger specs validate responses strictly, and the frontend's types are
  generated from `swagger/v1/swagger.yaml`: run `RAILS_ENV=test bundle exec rake rswag:specs:swaggerize`,
  then `npm run gen:api` in `frontend/`, and commit both. `npm run check:api` catches a stale
  `frontend/src/api/schema.d.ts`.

## Deploying

Production runs as an app on [fog](https://github.com/fogapp/fog), built from this repo
(see INSTALL.md, "Running on fog").
Fog reads `fog.yaml` on every deploy, so changes to sign-in or integration metadata
reach the installed app with its next release. Migrations apply in fog's
release phase, `bin/rails fog:release` (restore a staged backup if armed, then `db:prepare`),
so a merged migration runs on the next deploy.

Anything that genuinely can't ride the deploy — a new environment variable, a one-off
backfill — is a manual step on the server.

## Reference docs

`README.md` (overview), `INSTALL.md` (installing), `SETUP.md` (post-install configuration),
`ACCESS.md` (auth, tokens, MCP, webhooks), `docs/` (design notes), and `frontend/DESIGN.md` (design language).
