# Installing Fin

This guide takes a machine with nothing on it to a running Fin instance. It
covers three paths:

1. **Docker Compose** — the recommended way to run Fin locally. Everything
   (Postgres, Rails, the job worker, the Vite dev server) runs in containers.
2. **Native** — Ruby, Node, and Postgres installed directly on the host. Useful
   for day-to-day development if you already have the toolchain.
3. **Production** — the single-container image on any Docker host, or as an
   app on [fog](https://github.com/fogapp/fog), the self-hosting platform
   Fin is built to run on.

Once the app is up, continue with [SETUP.md](SETUP.md) to create your first
user and configure integrations, and [ACCESS.md](ACCESS.md) for logins, API
tokens, and webhooks.

---

## What you are installing

Fin is two processes plus a database:

| Piece | What it is | Runs as |
|---|---|---|
| Web | Rails 8.1 API (Ruby 4.0.9) that also serves the built React SPA from `public/` | `bin/rails server` (behind Thruster in production) |
| Worker | Solid Queue job runner for syncs, market data, workflows, backups | `bin/jobs` |
| Database | Postgres **18** with the `citext`, `pg_trgm`, and `pgcrypto` extensions | container or host service |

There is one database. Solid Queue (jobs) and Solid Cache (API caching) live in
it alongside the app tables, so a single `pg_dump` is a complete backup.

The frontend is a React 19 + Vite + TypeScript app in `frontend/`. In
development it runs as its own dev server on port 5173 and proxies `/api` to
Rails. In production it is built once into `public/` and served by Rails.

---

## Path 1: Docker Compose (recommended)

### Requirements

- Docker Engine 24+ with the Compose plugin (`docker compose version` works)
- ~2 GB free disk for images and the Postgres volume
- Git

### Steps

```sh
git clone https://github.com/fogapp/fin.git
cd fin
cp .env.example .env
docker compose up --build
```

The first boot's `db:prepare` creates the database and loads the demo seed
on its own. To see the seed's invite code and API token, run it again in a
second terminal (it is idempotent):

```sh
docker compose exec web bin/rails db:seed
```

Open **http://localhost:5173**. The seed prints an invite code and an API
token. Open `/register?invite=<code>`, enter `dev@fin.local`, and enroll a
passkey to sign in to the demo household. The token
(`dev-token-fin-local`) is for API and MCP calls. Details in
[ACCESS.md](ACCESS.md).

### What `docker compose up` starts

| Service | Image | Host port | Notes |
|---|---|---|---|
| `db` | `postgres:18-alpine` | 5432 | Data in the `db_data_18` volume, mounted at `/var/lib/postgresql` |
| `web` | `Dockerfile.dev` | **3001** → 3000 | Runs `bin/rails db:prepare` then the server. Health check hits `/up` |
| `worker` | `Dockerfile.dev` | none | `bin/jobs`; waits for `web` to be healthy so schema load happens once |
| `frontend` | `node:24-alpine` | **5173** | `npm install && npm run dev`; proxies `/api` to `http://web:3000` |

The repo is bind-mounted into `web` and `worker` at `/rails`, so code edits are
live without a rebuild. Gems are cached in the `bundle_cache` volume and
`bundle install` runs on every container start (the dev entrypoint does this;
the production image skips it).

`db:prepare` runs in the `web` service's command, not the entrypoint. That is
deliberate: only one process should create the schema and extensions, or the
worker races it on `CREATE EXTENSION pgcrypto`.

### The `.env` file

`.env.example` is the template. Only the database variables matter for a first
boot, and their defaults already match the compose file:

```
DATABASE_USER=fin
DATABASE_PASSWORD=fin
DATABASE_NAME=fin_development
DATABASE_NAME_TEST=fin_test
```

Every third-party API key in that file is optional at install time. Fin
prefers keys entered in **Settings → Integrations** (stored encrypted in the
database) and only falls back to the environment. Leave them blank now and
add them in [SETUP.md](SETUP.md).

Saving a key in Settings → Integrations needs the three `AR_ENCRYPTION_*`
values, which development does not generate for you. Print a set, paste
them into `.env`, and recreate the containers so they pick the values up:

```sh
docker compose exec web bin/rails db:encryption:init
docker compose up -d
```

`.env` is read by the `dotenv` gem in development and test only. It is never
loaded in production.

### Resetting

Drop everything, including the database volume, and start fresh:

```sh
docker compose down -v
docker compose up --build
docker compose exec web bin/rails db:seed
```

---

## Path 2: Native install

### Requirements

| Tool | Version | Notes |
|---|---|---|
| Ruby | **4.0.9** (`.ruby-version`) | Bundler 4 (`Gemfile.lock` says `BUNDLED WITH 4.0.3`) |
| Node | **24** (LTS) | Only pinned by the Docker images; no `.nvmrc`. Vite 8 needs 20.19+ or 22.12+ |
| Postgres | **18** | Client tools must be 18 too: `pg_dump` older than the server refuses to run, which breaks backups |
| System libs | `libpq-dev`, `libyaml-dev`, `pkg-config`, `build-essential`, `git` | Debian/Ubuntu names; use the Homebrew equivalents on macOS |
| Optional | `zstd`, `libvips`, `libjemalloc2` | Restoring older (fog-backup/1) backups, Active Storage variants, memory. Only needed to mirror production |

On macOS with Homebrew:

```sh
brew install postgresql@18 libyaml pkg-config zstd node@24
```

Install Ruby 4.0.9 with your version manager of choice (`rbenv install 4.0.9`,
`mise use ruby@4.0.9`, and so on).

### Database

Create a role and database that match the defaults in `config/database.yml`,
or set the `DATABASE_*` variables to whatever you prefer:

```sh
createuser -s fin
psql -c "ALTER USER fin PASSWORD 'fin';"
```

The extensions are created by the schema, so the role needs permission to
`CREATE EXTENSION` (a superuser in local dev is fine).

The relevant variables and their defaults:

| Variable | Default |
|---|---|
| `DATABASE_HOST` | `localhost` |
| `DATABASE_PORT` | `5432` |
| `DATABASE_USER` | `fin` |
| `DATABASE_PASSWORD` | `fin` |
| `DATABASE_NAME` | `fin_development` |
| `DATABASE_NAME_TEST` | `fin_test` |

### Backend

```sh
cp .env.example .env
bin/setup --skip-server     # bundle install, db:prepare (loads the demo seed on a new database), clears logs/tmp
bin/rails db:seed           # optional: reprints the demo invite code and API token
bin/rails server -p 3001    # API on http://localhost:3001
```

`bin/setup` without `--skip-server` finishes by starting the server for you.
Use port 3001 so the Vite proxy default works without configuration. On
macOS port 3000 is often already taken.

### Worker

```sh
bundle exec ruby bin/jobs
```

**macOS caveat:** the Solid Queue supervisor forks, and the `pg` gem can crash
in the forked child on macOS. If `bin/jobs` dies immediately, either run the
worker in Docker (`docker compose up worker`) or run a single in-process
worker from a Rails runner:

```sh
bin/rails runner 'SolidQueue::Worker.new(queues: "*", threads: 3).start'
```

Alternatively set `SOLID_QUEUE_IN_PUMA=1` to run the supervisor inside the
web process. This is fine for a single-user dev box.

### Frontend

```sh
cd frontend
npm install
npm run dev                 # http://localhost:5173, proxies /api → :3001
```

If your API is on a different port, set `API_TARGET`:

```sh
API_TARGET=http://localhost:3111 npm run dev
```

### Verify

```sh
curl -s http://localhost:3001/up                     # 200 from Rails
curl -s http://localhost:3001/api/v1/setup           # {"setup_required":true|false}
```

Run the test suites to confirm the toolchain is healthy:

```sh
bundle exec rspec                 # backend (needs Postgres; creates fin_test)
cd frontend && npm test           # Vitest
```

Other checks used before committing: `bin/rubocop`, `bin/brakeman`,
`bin/bundler-audit`, and in `frontend/`: `npm run lint` and `npm run build`.

---

## Path 3: Production

### The image

`Dockerfile` builds a single self-contained image: Ruby 4.0.9 slim (Debian trixie), Postgres 18
client, jemalloc preloaded, Node 24 used at build time to compile the SPA into
`public/`. The final stage runs as an unprivileged `rails` user and listens on
port **80** through Thruster.

```sh
docker build -t fin .
docker run -d -p 80:80 --name fin \
  -e SECRET_KEY_BASE=<64+ random hex chars> \
  -e DATABASE_HOST=... -e DATABASE_USER=... -e FIN_DATABASE_PASSWORD=... \
  -e AR_ENCRYPTION_PRIMARY_KEY=... \
  -e AR_ENCRYPTION_DETERMINISTIC_KEY=... \
  -e AR_ENCRYPTION_KEY_DERIVATION_SALT=... \
  -e GIT_SHA=$(git rev-parse HEAD) \
  fin
```

You also need a second container (or process) for the worker, running the same
image with the command `bundle exec ruby bin/jobs`.

**Nothing in the image runs migrations.** Before starting the web process,
run `bin/rails db:create db:schema:load` on first boot and `bin/rails
db:migrate` on every upgrade. Avoid `db:prepare` against an empty production
database: it also runs `db/seeds.rb`, which loads the development demo
household and its well-known API token.

### Required environment

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Rails secret. Also keys the HMAC behind every passkey user handle, so **never rotate it** on a live instance or existing passkeys stop working |
| `AR_ENCRYPTION_PRIMARY_KEY` | Active Record Encryption. Protects every stored provider credential (Plaid, Alchemy, Coinbase, ...) |
| `AR_ENCRYPTION_DETERMINISTIC_KEY` | as above |
| `AR_ENCRYPTION_KEY_DERIVATION_SALT` | as above |
| `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USER`, `DATABASE_NAME` | Postgres connection. `DATABASE_NAME` defaults to `fin_production` |
| `FIN_DATABASE_PASSWORD` | Production password. Note the different name from the dev `DATABASE_PASSWORD` |

The three encryption variables are fetched without defaults in production, so
**the app refuses to boot if any is missing**. This is intentional: a missing
key used to boot fine and fail only on the first encrypted read, which made
every integration silently unusable after a restore.

Generate keys once and store them somewhere safe. Losing them means losing
every stored API credential (the rest of the data is fine):

```sh
bin/rails db:encryption:init      # prints three fresh values
bin/rails secret                  # SECRET_KEY_BASE
```

Back up these values with the same care as the database. A backup restored
with different keys is refused at preflight (see Backups below).

### Optional environment

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `3000` | Puma port inside the container (Thruster fronts it on 80) |
| `RAILS_MAX_THREADS` | `3` Puma / `5` DB pool | Thread count |
| `JOB_CONCURRENCY` | `1` | Worker processes for the `default,workflows` queues |
| `RAILS_LOG_LEVEL` | `info` | |
| `GIT_SHA` | from `REVISION` file or `git rev-parse` | Rotates API cache keys and ETags. **Set it on every deploy** or clients can keep revalidating a stale payload shape |
| `FIN_OPEN_REGISTRATION` | `true` | Whether anyone can register a passkey. Set to `false` after creating your account (see ACCESS.md) |
| `FIN_WEBAUTHN_RP_ID`, `FIN_WEBAUTHN_ORIGINS`, `FIN_WEBAUTHN_RP_NAME` | derived from the request | Passkey relying party overrides. Not needed unless you serve the app under multiple hostnames. Origins are added to the request-derived ones, never instead of them, and each must be a scheme + host (`https://fin.example.com`) |
| `FOG_API_TOKEN` | unset | Credential for the `/fog/*` backup, restore, and integration endpoints. fog injects it. Unset, every `/fog/*` request answers 401 |
| `FOG_API_URL` | unset | fog's API, injected by fog. With `FOG_API_TOKEN` it turns on publishing to fog's event stream and fog-only sign-in (see ACCESS.md) |
| `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` | unset | Sign in with fog, or any OpenID provider (see ACCESS.md). fog injects them from `fog.yaml`. Unset means `/login` offers passkeys only |
| `FLARE_DSN` | unset | Error reporting through the vendored `flare` client. Inert without it |
| `GLASS_URL`, `GLASS_API_KEY` | unset | Metrics, traces, profiles, logs and browser analytics to Glass, an observability app that runs on fog. On fog, connecting Glass's `monitoring` offer on Fin's Integrations tab sets both. Inert without both |
| `OFFICE_URL`, `OFFICE_API_TOKEN` | unset | Instance-wide fallback for the Office integration (SETUP.md). On fog, Office's `documents` offer sets both |
| `SOLID_QUEUE_IN_PUMA` | unset | Run the job supervisor inside the web process instead of a separate worker |

Provider API keys (`ALPHA_VANTAGE_API_KEY`, `TIINGO_API_KEY`, `PLAID_CLIENT_ID`,
`PLAID_SECRET`, `PLAID_ENV`, `COINMARKETCAP_API_KEY`, `COINGECKO_API_KEY`,
`COINBASE_API_KEY_ID`, `COINBASE_API_KEY_SECRET`, `ALCHEMY_API_KEY`,
`RENTCAST_API_KEY`) all work as environment fallbacks but the supported route
is entering them in the UI, where they are stored encrypted per household.

### TLS and hostnames

Passkeys (WebAuthn) require a secure context: **HTTPS, or `localhost`**. Put the
app behind a reverse proxy that terminates TLS. The relying-party ID is derived
from the request's host, so the app works on any domain with no configuration,
but passkeys are bound to the hostname they were registered on and do not
transfer if you rename the site.

Fin does not enforce `config.hosts` or `force_ssl` itself. Do that at the
proxy.

### Processes

`Procfile` defines the two process types:

```
web: ./bin/thrust ./bin/rails server
worker: bundle exec ruby bin/jobs
```

`config/queue.yml` starts three worker pools inside the single `worker`
process: `default,workflows`; `market_data,backfill`; and `backup`. A job on a
queue not listed there never runs, so any new `queue_as` must be added to
that file. `config/recurring.yml` schedules the nightly syncs, sweeps, and the
monthly review. Cron times evaluate in the instance time zone, set in
Settings → Household → Time zone (default `America/Los_Angeles`).

### Running on fog

[fog](https://github.com/fogapp/fog) is a self-hosting platform for a
household's apps, and Fin is in its app catalog. Installing Fin from the
catalog builds this repo's `Dockerfile` and wires everything this section
otherwise asks you to do by hand:

- a Postgres 18 database (`fin_production`) with the `citext`, `pg_trgm`, and
  `pgcrypto` extensions, injected as `DATABASE_*` and `FIN_DATABASE_PASSWORD`;
- freshly generated `SECRET_KEY_BASE` and `AR_ENCRYPTION_*` secrets;
- `GIT_SHA` set to the deployed commit, and `FIN_WEBAUTHN_RP_ID` /
  `FIN_WEBAUTHN_ORIGINS` set to the app's domain;
- a `worker` process running `bundle exec ruby bin/jobs`, and a managed
  volume at `/rails/storage`.

Fog reads `fog.yaml` on every deploy: it registers Fin for household sign-in
and publishes Fin's `finance` integration offer (see ACCESS.md). It injects
`FOG_API_URL` and `FOG_API_TOKEN` and backs Fin up through the fog-backup/2
contract below.

Fog runs `bin/rails fog:release` as each deploy's release phase, before the
new release takes traffic: it restores a staged backup if one is armed, then
runs `db:prepare`, so migrations apply on every deploy.

The `MALLOC_CONF=background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:0`
setting is optional. It makes jemalloc return freed memory to the OS on an
idle instance instead of holding it indefinitely. Without it the containers
slowly grow over a day.

---

## Backups and restore

Fin implements fog's **fog-backup/2** contract
([backup-contract.md](https://github.com/fogapp/fog/blob/main/docs/backup-contract.md)),
but the pieces work without fog too.

A backup artifact is a tar containing a `manifest.json`, an uncompressed
custom-format `pg_dump` of the single database, and a plain tar of the
`storage/` tree. Nothing inside is compressed, so fog's deduplicating store
shares unchanged data between nights; it compresses what it keeps. Older
fog-backup/1 artifacts (a compressed dump and a zstd tar) still restore. The
manifest fingerprints the encryption keys and `SECRET_KEY_BASE`, records the
address the instance's passkeys are bound to (its host and WebAuthn
relying-party ID), and names the git SHA that produced it.

**Produce a backup from the console.** `/settings#topic=backup` → **Create
backup**, then **Download**. It is the same artifact fog collects, so it
restores through either door below. The section is for household admins; a
backup holds every household's data, so on an instance strangers can reach,
set `FIN_OPEN_REGISTRATION=false` (a new registration founds a household
and administers it).
Artifacts stay under `storage/fog/backup/` for 24 hours and are then swept.

**Produce a backup over the API** (requires `FOG_API_TOKEN`):

```sh
curl -X POST -H "Authorization: Bearer $FOG_API_TOKEN" https://fin.example.com/fog/backup
# → {"job":"<id>"} ; poll GET /fog/backup/jobs/<id>, then
curl -H "Authorization: Bearer $FOG_API_TOKEN" -o fin.fogpack.tar \
  https://fin.example.com/fog/backup/jobs/<id>/artifact
```

Without fog, a plain `pg_dump -Fc` of the database plus a copy of `storage/`
and your environment variables is an equivalent backup.

**Restore onto a fresh instance.** Boot the new instance with the *same*
`SECRET_KEY_BASE` and `AR_ENCRYPTION_*` values (the Backup section's
**Instance keys** shows them and downloads them as a `.env`), then before
creating any user:

- Open the registration page. A fresh instance offers a "restore from backup"
  door that uploads the artifact to `POST /api/v1/setup/restore`, or
- on fog, attach the artifact under "Migrating from another instance?" while
  installing; fog asks for the same keys and checks them against the
  artifact, or
- `POST /fog/restore` with the artifact as the `artifact` multipart field.

Either route runs a preflight (format, app identity, key fingerprints), stages
the artifact under `storage/fog/restore/`, arms a restore, and restarts the
app. `bin/docker-entrypoint` sees the armed restore on boot, runs
`bin/rails fog:restore_if_staged`, and only then starts serving. A failed
restore exits non-zero on purpose rather than booting half-restored.

Both restore endpoints refuse once a user exists. Restoring over a live
instance is a fog operation that stops the app first.

### Moving to a new address

A backup restores at any address, and everything in it comes along. Two things
are bound to the old address and need a hand:

- **Passkeys.** A passkey only works at the hostname it was registered on, so
  after a restore elsewhere nobody's passkey signs in. Before moving, create a
  sign-in link for each member in the Backup section (**Moving to a new
  address**). A link is good for a week, works once, and only at the address
  it was made for; opening it there registers a new passkey. The links are
  signed with `SECRET_KEY_BASE`, which is why they still verify on the
  restored instance. If the old instance is already gone, print one on the
  new server instead:

  ```sh
  bin/rails "fin:sign_in_link[you@example.com,fin.example.com]"
  ```

- **Alchemy webhooks.** They keep delivering to the old URL. Set the webhook
  base URL under Settings → Integrations → Alchemy; saving re-registers them.

Because the artifact names the address it came from, a restore at a different
one is refused until it is confirmed: a checkbox on the registration page's
restore door and in fog, `confirm_identity` on the API. After a confirmed
move, each household gets an entry under Settings → Issues naming what still
points at the old address. API tokens are unaffected; repoint MCP and API
clients at the new URL. Retire the old instance once the new one is up, or
both will keep syncing the same accounts.

---

## Upgrading

```sh
git pull
bundle install
cd frontend && npm install && cd ..
bin/rails db:migrate
```

In Docker Compose, `docker compose up --build` covers all of the above except
that `db:prepare` (which includes migrate) runs at `web` start.

If a release adds a queue to `config/queue.yml` or a schedule to
`config/recurring.yml`, restart the worker so it picks them up.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `web` container exits with a `KeyError` for `AR_ENCRYPTION_*` | Production boot requires all three keys. Set them |
| White screen after a deploy, API returns 304 forever | `GIT_SHA` was not updated. Set it to the new commit and restart |
| Passkeys do not work over plain HTTP | WebAuthn needs HTTPS or `localhost`. Terminate TLS at the proxy |
| Every passkey ceremony fails with `OriginVerificationError` | `FIN_WEBAUTHN_ORIGINS` names an origin the browser never sends. The log says which entries were ignored and what the request's own origin was; unset the variable to derive it from the request |
| Backup job fails immediately | `pg_dump` older than the server. The image ships the 18 client; native installs must too |
| Jobs enqueued but never run | The queue is not listed in `config/queue.yml`, or the worker is not running |
| `bin/jobs` segfaults on macOS | Fork-safety issue in the `pg` gem. Use the Docker worker or an in-process worker (see Native → Worker) |
| Vite shows the app but every API call 404s | `API_TARGET` points at the wrong port. Default is `http://localhost:3001` |
