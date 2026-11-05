# Accessing Fin

Every way in, what credential each one takes, and where those credentials
come from.

## Summary

| Surface | Path | Credential |
|---|---|---|
| Web console | `/` | Passkey (WebAuthn), or sign in with fog (OpenID Connect). No passwords exist |
| REST API | `/api/v1/*` | `Authorization: Bearer <api token>` |
| API reference | `/api-docs` | none (Swagger UI) |
| MCP server | `POST /mcp` | same bearer API token |
| Health | `GET /up` | none |
| Alchemy webhooks (inbound) | `POST /webhooks/alchemy` | HMAC signature from Alchemy |
| Backup, restore, integrations (fog) | `/fog/*` | `Authorization: Bearer $FOG_API_TOKEN` |

There is no default username or password. On a fresh instance the first
person to open `/register` creates the first account. On a seeded development
instance, see "Development credentials" below.

---

## Signing in

### Passkeys

Fin authenticates humans with passkeys only. The browser needs a **secure
context**: HTTPS in production, or `http://localhost` in development. Plain
HTTP on a LAN hostname will not work.

- `/register` creates an account: email, optional name, then the platform
  passkey prompt. The first registration creates a household and makes you
  its admin.
- `/login` signs in. Email is optional; it only narrows the passkey picker.
  The landing page's **Sign in** button tries a passkey immediately and falls
  back to `/login` if the device has none.
- Passkeys are bound to the hostname they were created on (the WebAuthn
  relying-party ID, derived from the request host). If you move the instance
  to a new domain, everyone re-enrolls through a sign-in link issued for the
  new address (see "Moving to a new address" in [INSTALL.md](INSTALL.md)).

A successful login mints a **session token**: an API token with a 30-day
expiry that the SPA keeps in `localStorage` under `fin_api_token`. Session
tokens are hidden from the API Tokens list. Signing out forgets the token in
the browser but does not revoke it server-side; it expires on its own. If a
device is lost, remove its passkey from Devices and delete its session rows
from a console.

### Sign in with fog

When `OIDC_ISSUER`, `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` are set — fog
injects them for an app that declares `signin:` in `fog.yaml`, and any other
OpenID provider works the same way — `/login` offers **Sign in with fog**
(fog's [sign-in contract](https://github.com/fogapp/fog/blob/main/docs/signin-contract.md)).
fog signs people in to Fin only with a passkey (`acr: phr`), and decides who
may: the app's Sign-in tab in fog.

- **The first sign-in on an empty Fin is its registration.** fog's
  operator gets a household (with the default workflows) and is its admin.
- **Accounts are never matched by email.** Someone fog signs in whose fog
  identity is not yet connected to a Fin account lands on `/auth/link`:
  they sign in to their existing account with its Fin passkey, once, to
  connect it, or start fresh (a new account in the instance's first
  household, the oldest, with the role fog gave them). An account connects to one person
  at a provider.
- **Roles.** fog's role (`admin`/`member`) is applied, on every sign-in, to
  the person's membership in that first household. Their other
  households' roles are Fin's own. The household's last admin is never
  demoted.
- **Sessions** are the usual 30-day session tokens, landing in the household
  the person joined first. Each remembers fog's session id, including across
  a household switch, so when the person signs out of fog, is removed or
  suspended, fog's back-channel logout (`POST /auth/oidc/backchannel`) ends
  exactly those sessions. Personal API tokens are not touched.
- **Fog only.** Once Fin proves it runs on fog — the fog that knows its
  `FOG_API_TOKEN` signs, with the key behind its ID tokens, the issuer and
  client Fin is configured with — Fin's own passkey sign-in,
  registration (whatever `FIN_OPEN_REGISTRATION` says) and device links
  are closed, and `/login` offers fog alone. Passkeys remain only for
  connecting an account on `/auth/link`. This is sticky while the `FOG_*`
  variables are set; a fog that cannot be reached never re-opens local
  sign-in.
- **Break-glass:** with fog broken, a shell on the server runs
  `bin/rails "fin:recovery_link[fin.example.com]"`, which prints a
  single-use, ten-minute sign-in link for the first admin and records it in
  the activity log.

### Registration policy

`FIN_OPEN_REGISTRATION` (default `true`) controls whether `/register` works
without an invite. Leave it open until your account exists, then set it to
`false`. After that:

- New people need an **invite code** (below).
- An existing account with no passkey (for example, the seeded dev user)
  also needs an invite code or a device link. Knowing an email address is
  never enough to enroll a credential.
- An email that already has a passkey is told to sign in instead.

### Adding people: invite codes

Admins create invites at `/settings#topic=household` → Invites, choosing a
role and an expiry (default 7 days). The result is a link:

```
https://fin.example.com/register?invite=<code>
```

The invitee registers with the code and joins your household with that role.
Codes are single-use, revocable while unused, and kept afterwards as an audit
trail. `GET /api/v1/invites/:code` is public and returns only the household
name, role, and expiry so the register page can show who is inviting.

### Adding devices: device links

Your own additional devices do not need invites. At
`/settings#topic=devices` → **Generate device link**, Fin produces

```
https://fin.example.com/join-device?token=<signed token>
```

valid for 15 minutes. Open it on the new device to enroll a second passkey
for the same account. The Devices page also lists, renames, and removes
passkeys. Removing your only passkey is refused.

`POST /api/v1/device_invites` with an `address` issues the long-lived form
used when the instance moves: a **sign-in link** valid for 7 days, redeemable
once and only at that host. An admin may add `user_id` to issue one for
another member of the household, which is how members get back in at the new
address. `/settings#topic=backup` is the UI for it. Treat a link like a
password until it is used: whoever opens it first enrolls a passkey on that
account.

### Roles and households

Two roles: `admin` and `member`. Admins manage members, invites, integrations,
and household settings; members use the data. The last admin cannot be demoted
or removed.

A user can belong to several households. Login lands in the one you joined
first; `POST /api/v1/auth/switch_household` (the household menu in the UI)
mints a new token scoped to another. **Every API token is scoped to exactly
one (user, household) pair.**

---

## Development credentials

`bin/rails db:seed` creates a household named **Default** with demo data and:

| Item | Value |
|---|---|
| User | `dev@fin.local` (admin) |
| API token | `dev-token-fin-local` |
| Invite code | printed by the seed; also `InviteCode.usable.last.code` in a console |

The token works immediately for the REST API and MCP:

```sh
curl -H "Authorization: Bearer dev-token-fin-local" http://localhost:3001/api/v1/me
```

To use the web UI as that user, enroll a passkey with the invite:
`http://localhost:5173/register?invite=<code>`, email `dev@fin.local`.
Registering with any other email creates a fresh household with no demo data.

Do not run the seed in production. It creates a well-known token. Note that
`bin/rails db:prepare` against an empty database runs the seed too (see
INSTALL.md, Production).

---

## API tokens

Long-lived tokens for scripts, the MCP server, and other API clients.

**In the UI:** `/settings#topic=tokens`. Give the token a name and an optional
expiry, create it, and copy it from the one-time reveal. Fin stores only a
SHA-256 digest; the plaintext is never shown again. The same page lists each
token's last use and lets you revoke it.

**From the API** (with an existing token):

```sh
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"laptop script","expires_at":"2027-01-01"}' \
  https://fin.example.com/api/v1/api_tokens
# → {"id":"…","name":"laptop script","token":"<plaintext, this response only>", …}
```

**From a console** (useful on a fresh production instance before any UI
token exists):

```sh
bin/rails runner 'u = User.find_by!(email: "you@example.com"); h = u.households.first
t = ApiToken.create!(user: u, household: h, name: "console"); puts t.raw_token'
```

Properties:

- 64 hex characters, generated server-side.
- Scoped to one user and one household, with one of two scopes. `full`,
  what the UI and the API mint, can do everything its user can do in that
  household. `read` answers `GET` and `HEAD` and the MCP tools only;
  anything else is a 403 (`This token can only read Fin, not change
  it.`). Read tokens are what fog mints for another app (below), or what a
  console mints with `scope: "read"`. The token list shows which is which.
- Optional `expires_at`. Expired tokens return 401 `Token expired`.
- Revoking is `DELETE /api/v1/api_tokens/:id`. You can only revoke your own.

Tokens created by the seed are plain database rows and can be deleted the
same way.

### Apps connected by fog

On fog, another app on the same server (a dashboard's net-worth widget,
say) can be connected to Fin from its Integrations tab in fog without
anyone copying a key (fog's
[integrations contract](https://github.com/fogapp/fog/blob/main/docs/integrations-contract.md),
Fin's `finance` offer in `fog.yaml`). Because a Fin token acts as a person on the household's
money, fog's operator clicking is not enough: fog sends them to
`/connect/<ticket>` on Fin's console, where a **household admin** sees
which app is asking and what it would get, and approves or declines.
Approving mints a `read` token in the approver's name, named `fog: <app>`,
which fog collects once and puts in that app's environment as
`FIN_API_TOKEN` (with `FIN_URL`). The request expires after 30 minutes
if nobody answers.

The token is an ordinary row in the approver's token list, marked
read-only, and can be revoked there; fog then shows the app as
disconnected. Disconnecting in fog revokes it the other way round. The
machine side — `POST /fog/integrations`, `/claim`, `GET` and `DELETE
/fog/integrations/:id` — is authenticated by `FOG_API_TOKEN` like the
backup surface, never by API tokens or sessions.

---

## The REST API

Base path `/api/v1`. JSON in, JSON out. Every request except the ones listed
under "Unauthenticated endpoints" needs the bearer header. Household scoping
is applied server-side from the token; there is no household parameter.

```sh
H="Authorization: Bearer $TOKEN"
B=https://fin.example.com/api/v1

curl -H "$H" $B/me                         # who am I, which household, role
curl -H "$H" $B/dashboard
curl -H "$H" $B/net_worth?range=1y
curl -H "$H" "$B/cash_transactions?from=2026-01-01&to=2026-01-31&limit=100&offset=0"
curl -H "$H" "$B/search?q=whole+foods"
curl -H "$H" $B/portfolio
curl -H "$H" $B/budget?month=2026-09
curl -H "$H" -X POST $B/workflows/<id>/run_now
```

The full reference with schemas is the Swagger UI at **`/api-docs`**
(source: `swagger/v1/swagger.yaml`, regenerated from request specs with
`bundle exec rake rswag:specs:swaggerize`). The main resource families:

| Area | Endpoints |
|---|---|
| Identity | `me`, `about`, `preferences`, `api_tokens`, `webauthn_credentials`, `device_invites`, `invites`, `households`, `household_memberships`, `auth/switch_household`, `fog_connections` |
| Money | `cash_transactions` (+ `filter`, `bulk_update`, tags), `accounts`, `brokers`, `loans`, `transfers`, `saved_views`, `saved_reports`, `imports` |
| Classification | `merchants`, `categories`, `tags`, `workflows`, `workflow_runs`, `activity` |
| Reporting | `dashboard`, `net_worth`, `cashflow` (+ `activity`, `sankey`, `spend_breakdown`), `budget`, `subscriptions`, `review`, `stats`, `search` |
| Investing | `portfolio`, `investment_transactions`, `buys`, `sells`, `dividends`, `crypto`, `cost_basis`, `investment_lots`, `market` (securities), `security_conversions`, `security_labels`, `benchmarks`, `reconciliation`, `real_estate_properties`, `equity/*`, `tax/*`, `tax_profile` |
| Providers | `plaid/*`, `coinbase/*`, `alchemy/*`, `office/*`, `alpha_vantage/configuration`, `tiingo/configuration`, `coin_market_cap/configuration`, `rentcast/configuration` |
| Health and admin | `system_health`, `issues`, `notifications`, `backups`, `setup` |

Conventions:

- IDs are UUID strings.
- Amounts are decimal strings in USD unless a `currency` field says
  otherwise. On cash transactions, negative is spend and positive is income.
- Date-only fields are `YYYY-MM-DD`.
- Errors are `{"error": "…"}` or `{"errors": ["…"]}` with a 4xx status.
- Endpoints that enqueue work (`sync`, `refresh`, `run_now`, `backfill`)
  return **202** with the job reference rather than waiting.
- Lists page with `limit` and `offset`. There is no total count header; the
  end is a short page.
- Responses carry strong ETags keyed to the deployed git SHA. Clients may
  revalidate with `If-None-Match`.

### Unauthenticated endpoints

| Endpoint | Purpose |
|---|---|
| `GET /up` | Health check |
| `GET /`, any SPA path | Serves the console |
| `GET /api-docs` | Swagger UI and spec |
| `GET /api/v1/setup` | `setup_required` while no user exists, and `signin: {enabled, fog_only}` |
| `GET /auth/oidc/{start,callback}`, `POST /auth/oidc/link` | Sign in with fog (404 without `OIDC_*`) |
| `POST /auth/oidc/backchannel` | fog's back-channel logout; a logout token signed by the provider |
| `POST /api/v1/handoff` | Trades a sign-in's one-time, one-minute code for its session (20 per minute) |
| `POST /api/v1/auth/passkey/link/{begin,finish}` | The link page's passkey proof (needs a live pending fog sign-in) |
| `POST /api/v1/setup/restore` | Restore a backup on a fresh instance (5 per 10 min) |
| `POST /api/v1/auth/passkey/register/{begin,finish}` | Registration ceremony |
| `POST /api/v1/auth/passkey/login/{begin,finish}` | Login ceremony |
| `POST /api/v1/auth/passkey/device_invite/{begin,finish}` | Device-link and sign-in-link enrolment |
| `GET /api/v1/backups/:id/artifact` | Backup download; needs the 5-minute ticket from `POST /api/v1/backups/:id/download` |
| `GET /api/v1/invites/:code` | Invite preview |
| `POST /webhooks/alchemy` | Signature-verified provider webhook |

Everything else is 401 without a valid token. There is no rate limiting
beyond the restore and handoff endpoints, and no CORS layer: the SPA is
same-origin, and API clients are expected to be non-browser.

---

## MCP

Fin exposes a [Model Context Protocol](https://modelcontextprotocol.io)
server at `POST /mcp` (Streamable HTTP, stateless JSON-RPC; `GET` and
`DELETE` return 405). It runs inside the web process, so it is live wherever
the app is. Authentication is the same bearer API token, and every tool is
read-only and scoped to that token's household.

Tools:

| Tool | Returns |
|---|---|
| `list_accounts` | Accounts with balances |
| `search_transactions` | Filtered cash transactions |
| `get_net_worth` | Net worth and breakdown |
| `get_cashflow` | Income vs spend for a period |
| `get_budget` | Budget lines and pace for a month |
| `get_dashboard` | The dashboard payload |

Connect from Claude Code:

```sh
claude mcp add --transport http fin https://fin.example.com/mcp \
  --header "Authorization: Bearer <api token>"
```

Any MCP client that speaks Streamable HTTP with a custom header works the
same way. Use a dedicated token named for the agent so you can revoke it
independently.

---

## Webhooks

### Inbound: Alchemy

The only inbound webhook. When Alchemy is configured with a Notify auth token
and a public base URL, Fin registers one address-activity webhook per
network pointing at:

```
POST https://fin.example.com/webhooks/alchemy
```

Each delivery is verified with HMAC-SHA256 of the raw body against that
webhook's signing key (header `X-Alchemy-Signature`) using a constant-time
compare. Bad signatures get 401 and an Activity entry. A valid delivery only
schedules a targeted sync 90 seconds later; the poll is the source of truth,
so a missed webhook loses nothing.

There is no Plaid webhook. Plaid is polled.

### Outbound: workflow `webhook` action

Any workflow step can include a **webhook** action with an HTTPS URL. On each
run Fin POSTs:

```json
{
  "event_type": "cash_transaction.created",
  "workflow": "Big purchases to Home Assistant",
  "run_id": "…",
  "subject_type": "CashTransaction",
  "subject_id": "…",
  "event_payload": { "…": "…" },
  "subject": { "amount": "-1250.00", "description": "…", "…": "…" }
}
```

Only fields whitelisted in the workflow catalog are included in `subject`.
Delivery rules: HTTPS only, 5-second connect and read timeouts, redirects not
followed, response body ignored. The run log records `delivered` or
`rejected` with the status code. **Outbound payloads are not signed**; use a
URL with an unguessable path or a receiver on a private network.

### Outbound: notification webhook

Independently of workflows, every in-app notification can be mirrored to one
URL per household (an ntfy topic, Home Assistant, a relay). The body is
`{title, body, severity, workflow, event_type}`. This is set from a console
only:

```sh
bin/rails runner 'Household.find_by!(name: "…").update!(notification_webhook_url: "https://ntfy.sh/your-topic")'
```

### Outbound: fog's household event stream

On fog, Fin also publishes to fog's event stream (fog's
[events contract](https://github.com/fogapp/fog/blob/main/docs/events-contract.md)),
where a reader such as HUD decides what each event deserves. There is nothing to configure: the `FOG_API_URL` and
`FOG_API_TOKEN` fog injects are the whole setup, and off fog nothing is sent.

- Every in-app notification goes out as `fin.notification`, with id
  `notification-<id>` and data `{title, body, link, severity, workflow,
  event_type}`: what the bell menu and the ntfy push already show. The ntfy
  push carries on unchanged beside it.
- A workflow's `fog_event` action ("send to HUD") publishes `fin.<type>`,
  the type defaulting to the run's trigger (`fin.budget.category_exceeded`;
  a scheduled or monitor run uses the workflow's name). Its data is the
  templated `title`, `body`, `link` and optional `key`, plus `severity`,
  `workflow`, `event_type`, `run_id` and the subject's type and id, never a
  snapshot of the subject.

Publishing never holds anything up: notifications publish from a job, with
3-second timeouts, and a refused or unreachable publish is recorded on the
activity timeline as `fog` / `event.failed`. A `fog_event` step reports it
as a step error, like a refused `webhook`.

Fin has no email and no mobile push. These webhooks and the event stream are
the way out.

---

## Backup and restore surface (fog)

`/fog/backup` and `/fog/restore` implement fog's fog-backup/2 contract, and
still restore fog-backup/1 artifacts. They are authenticated by a single
shared secret, `FOG_API_TOKEN`, presented as a bearer token. If that variable is
unset the whole surface answers 401. It deliberately bypasses users and
household scoping so a fresh, user-less instance can be restored into.

| Endpoint | Purpose |
|---|---|
| `GET /fog/backup` | Descriptor: app identity, fingerprints, whether the instance is fresh |
| `POST /fog/backup` | Start producing an artifact; 202 with a job id |
| `GET /fog/backup/jobs/:id` | Job status with `bytes` and `sha256` when done |
| `GET /fog/backup/jobs/:id/artifact` | Download the `.fogpack.tar` |
| `DELETE /fog/backup/jobs/:id` | Discard the staged copy |
| `POST /fog/restore` | Stage and arm a restore (fresh instances only) |

See [INSTALL.md](INSTALL.md) for the artifact format and what restore does on
boot.

### From the console

`/api/v1/backups` is the same producer behind the normal token stack, for
`/settings#topic=backup`. Any household admin may use it, and a backup is
instance-wide — every household's data. Since open registration lets anyone
found a household they administer, set `FIN_OPEN_REGISTRATION=false` on an
instance strangers can reach.

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/backups` | Staged manual backups, the instance's address, key fingerprints |
| `POST /api/v1/backups` | Start producing an artifact; 409 while fog is producing its own |
| `POST /api/v1/backups/:id/download` | A download URL valid for 5 minutes |
| `GET /api/v1/backups/:id/artifact?ticket=…` | The `.fogpack.tar`; authenticated by the ticket, not a bearer token |
| `DELETE /api/v1/backups/:id` | Discard the staged copy |
| `POST /api/v1/backups/keys` | The values of `SECRET_KEY_BASE` and `AR_ENCRYPTION_*` |

`POST /api/v1/backups/keys` is the one endpoint that returns server secrets.
A restore needs them on the new instance, and the alternative is reading them
off the host by hand. Every call is written to the activity log, as are
backup requests, downloads, and issued sign-in links.

---

## Where credentials live

| Credential | Storage | Rotating it |
|---|---|---|
| Passkeys | `webauthn_credentials` table (public keys only) | Remove and re-enroll from Devices |
| API and session tokens | `api_tokens` table, SHA-256 digest only | Revoke and create a new one |
| Invite codes, device links | `invite_codes` table; device links are signed, 15-minute, not stored | Revoke unused invites from Household settings |
| Provider API keys (Plaid, Tiingo, Alchemy, ...) | Provider configuration tables, encrypted with Active Record Encryption | Re-enter in Integrations |
| `AR_ENCRYPTION_*` keys | Environment | Cannot be rotated in place. Losing them makes every stored provider key unreadable |
| `SECRET_KEY_BASE` | Environment | Signs challenges, device links, and passkey user handles. Rotating it breaks existing passkeys |
| `FOG_API_TOKEN` | Environment | Set a new value and restart |
| Alchemy webhook signing keys | `alchemy_webhooks` table | Re-saving the Alchemy config re-registers webhooks |
| Office API token | `office_configurations` table (encrypted), else `OFFICE_API_TOKEN` in the environment | Revoke it in Office, mint another, and re-enter it in Integrations |

Passkey challenges are stateless, signed with the app secret, and expire
after 5 minutes. Nothing about a login attempt is stored until it succeeds.
