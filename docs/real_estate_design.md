# Real Estate — design

Track owned properties as a first-class asset class: enter an address, let RentCast
value it weekly, chart the value over time, and roll the total into net worth. Works
fully without the integration (manual valuations); RentCast just automates the numbers.

Lives as a **Real Estate** section inside `/investments`, alongside Portfolio / Crypto /
Net Worth / Equity.

## Decisions this design encodes

| Question | Decision |
|---|---|
| Value history | RentCast has **no** value-history endpoint. Seed from `taxAssessments` + sale `history` + purchase price on first sync; weekly AVM extends it forward. |
| Tax assessments | Charted as a **separate dimmed reference line**. Never used as market value, never counted in net worth. |
| Mortgage | The **loan points at the property** (`loans.real_estate_property_id`). Enables equity / LTV display. |
| Rent estimates | Out of scope. No `/avm/rent/long-term` calls. |
| Net worth | New **`real_estate` bucket**, **gross value**. The linked mortgage keeps counting as a liability under `loans`, so equity falls out and nothing double-counts. |
| Manual vs auto | **Newest `as_of` date wins.** Deterministic tiebreak on same date (below). |
| Refresh | Weekly per property + quarterly facts refresh + monthly quota guard + "Refresh now". |

## RentCast API facts (verified against the docs)

- Base `https://api.rentcast.io/v1`, auth via `X-Api-Key` header. Free tier: **50 requests/month.**
- `GET /avm/value?address=…` → `price`, `priceRangeLow`, `priceRangeHigh` (85% confidence),
  `subjectProperty` (beds/baths/sqft/year built/lat/long/last sale), `comparables[]`.
  **Current estimate only — one point in time.**
- `GET /properties?address=…` → full record in one call, including:
  - `taxAssessments`: year-keyed map → `{ year, value, land, improvements }`
  - `history`: date-keyed map → `{ event: "Sale", date, price }`
  - `lastSaleDate`, `lastSalePrice`, `propertyType`, `bedrooms`, `bathrooms`,
    `squareFootage`, `lotSize`, `yearBuilt`, `hoa.fee`, `features{…}`, `owner{…}`
- No value-history endpoint exists. The chart is therefore assembled from four
  sources we store ourselves.

### Quota math

Per property per month: 4 weekly AVM calls + ~0.33 facts calls (quarterly) ≈ **4.3**.
Three properties ≈ **13 / 50**. Comfortable, and the guard below keeps it that way.

## Data model

### `real_estate_properties`

```
id                uuid pk
household_id      uuid not null            # HouseholdScoped
name              string not null          # "Primary residence", user's label
address_line1     string not null
address_line2     string
city, state, zip_code
formatted_address string                   # RentCast's canonical form
rentcast_id       string                   # RentCast's slug id, e.g. "5500-Grand-Lake-Dr,-…"
latitude, longitude   decimal

property_type     string                   # facts cache, from /properties
bedrooms          integer
bathrooms         decimal(4,1)
square_footage    integer
lot_size          integer
year_built        integer
hoa_fee           decimal(15,2)

purchase_date     date                     # user-entered; seeds a Purchase valuation
purchase_price    decimal(15,2)
status            string not null default "owned"     # owned | sold
sold_date         date
sold_price        decimal(15,2)

sync_enabled      boolean not null default true       # off for addresses RentCast can't find
notes             text
facts_synced_at   datetime
last_synced_at    datetime
last_sync_error   string
timestamps
index (household_id), index (household_id, status)
```

`status: sold` freezes the property out of net worth from `sold_date` forward without
deleting its history. (Deleting the record would throw away the value curve.)

**Not included, easy to add later:** `ownership_percent` for partially-owned property,
`hidden` flag, rental income tracking.

### `real_estate_valuations`

One row per (property, source, date). This is the whole chart.

```
id                        uuid pk
household_id              uuid not null
real_estate_property_id   uuid not null
as_of                     date not null
amount                    decimal(15,2) not null
source                    string not null    # T::Enum below
value_low, value_high     decimal(15,2)      # AVM 85% range, rentcast only
payload                   jsonb              # raw response slice, for debugging
timestamps
unique index (real_estate_property_id, source, as_of)   # re-sync is idempotent
index (real_estate_property_id, as_of)
```

```ruby
class Source < T::Enum
  Rentcast      = new("rentcast")        # weekly AVM
  Manual        = new("manual")          # you typed it
  Purchase      = new("purchase")        # from purchase_price/purchase_date
  Sale          = new("sale")            # deed events from /properties history
  TaxAssessment = new("tax_assessment")  # reference line only
end

MARKET_SOURCES = [Rentcast, Manual, Purchase, Sale]   # what counts as value
```

The unique index is what makes re-syncing safe: two AVM pulls in the same day update
one row rather than stacking. Manual and RentCast values for the same day coexist as
two rows — the precedence rule picks between them.

### Current value — "newest date wins"

```ruby
# RealEstateProperty#current_valuation
valuations.where(source: MARKET_SOURCES)
          .order(as_of: :desc, source_rank: :desc, created_at: :desc)
          .first
```

Same-day tiebreak by explicit rank: **manual > rentcast > sale > purchase**. So a value
you type today beats that morning's sync, and next week's sync beats it back — which is
what "newest wins" means in practice. Implemented as a small `SOURCE_RANK` hash ordering
in Ruby rather than SQL gymnastics, since the row count per property is tiny.

`sold` properties resolve to `sold_price` at `sold_date` and contribute nothing after.

### `loans.real_estate_property_id`

Nullable uuid + index. A mortgage points at the property it finances.

- Property detail shows: value, linked loan's current balance, **equity**, **LTV**.
- Loan detail shows the linked property.
- Net worth is untouched by the link — the loan is already a liability, the property is
  already an asset. The link is display + the equity metric only.

### `rentcast_configurations`

Mirrors `TiingoConfiguration` / `AlchemyConfiguration` (`HouseholdScoped`, `encrypts :api_key`)
plus quota state:

```
id, household_id, api_key (encrypted text)
monthly_request_limit  integer not null default 50
requests_used          integer not null default 0
quota_period_start     date                      # month boundary; counter resets on roll
sync_frequency         string not null default "weekly"
last_synced_at         datetime
timestamps
```

## Services

### `Rentcast::Client`

`Net::HTTP` wrapper matching `AlchemyClient`'s shape — `Rentcast::Error` for user-facing
failures, key resolved from config then `ENV["RENTCAST_API_KEY"]`.

```ruby
property_record(address:)   # GET /properties?address=…
value_estimate(address:)    # GET /avm/value?address=…
test_connection!            # cheap known-address lookup for the settings "Test" button
```

Every request routes through `RentcastConfiguration#consume_quota!`, which rolls the
counter on a new month and raises `Rentcast::QuotaExceeded` at the limit — so the guard
can't be bypassed by a stray call site. HTTP 429 maps to the same error.

### `RealEstate::PropertyRefresher`

Refreshes one property. The only thing that writes valuations from RentCast.

1. `value_estimate` → upsert `Rentcast` valuation at `Date.current` with low/high.
   Also opportunistically fills empty facts from `subjectProperty` (free — same response).
2. If `facts_synced_at` is nil or older than 90 days → `property_record`:
   - update facts cache (type, beds, baths, sqft, lot, year, HOA, lat/long, `rentcast_id`)
   - upsert one `TaxAssessment` valuation per year, dated **Dec 31 of that year**
   - upsert one `Sale` valuation per `history` sale event, plus `lastSalePrice`/`lastSaleDate`
3. On success: clear `last_sync_error`, `Issue.resolve!("rentcast_property_#{id}")`.
   On failure: record the message, `Issue.raise_once!` with severity warning.

**First sync after adding a property runs both calls** — that's what populates the
assessment and sale history immediately, so the chart isn't empty on day one.

### Jobs

- `RealEstate::RefreshJob(property_id)` — one property; used by the weekly fan-out and
  the "Refresh now" button.
- `RealEstate::SyncTickJob` — weekly fan-out per household. Skips properties with
  `sync_enabled: false` or `status: sold`. **Budget guard:** before enqueueing, check
  `remaining_quota >= properties_to_sync`; if not, sync nothing, raise an Issue naming
  the shortfall. Reserving rather than partially syncing keeps the chart's properties
  in step with each other.
- `config/recurring.yml`: `real_estate_sync` → `every monday at 6:15am` (ahead of the
  6:45am `metrics_refresh`, so net-worth metrics see fresh values).

## Net worth integration

`NetWorthHistory` gets a fifth group. Concretely (`app/services/net_worth_history.rb`):

- `#call` — load `RealEstateProperty.owned`, build `points_by_property` (valuation
  breakpoints, market sources only, warmup point before the window, current value as
  today's point — same carry-forward shape as `balance_breakpoints_by_account`, so
  `values_at` is reused unchanged).
- `#resolve_range_start` — include earliest valuation date among the `all` candidates,
  so a 2018 purchase widens the chart.
- `#valuation` — `real_estate:` key; added to `assets`.
- `#series_row` and `#stats` — emit `real_estate:` (positive, an asset).
- New `properties:` breakdown array alongside `accounts:` / `loans:`, with value /
  start_value / change / change_pct and the linked mortgage balance + equity.

Frontend counterparts: `NetWorthGroup` union, `NetWorthSeriesPoint`, `NetWorthStats`,
`NetWorthPropertyRow` in `api/types.ts`; a `{ key: "real_estate", label: "Real Estate",
slot: 3, liability: false }` entry in `NetWorth.tsx`'s series config.

**To verify during implementation:** whether `Metrics::Definitions`' net-worth metrics read
`NetWorthHistory` (in which case they inherit this for free) or recompute from accounts
(in which case they need the same addition).

## API

```
GET    /api/v1/real_estate_properties                    # list + current value + equity
POST   /api/v1/real_estate_properties                    # address; resolves via RentCast if configured
GET    /api/v1/real_estate_properties/:id                # detail + valuation series + facts
PATCH  /api/v1/real_estate_properties/:id
DELETE /api/v1/real_estate_properties/:id
POST   /api/v1/real_estate_properties/:id/refresh        # sync now (spends quota)
POST   /api/v1/real_estate_properties/:id/valuations     # manual { amount, as_of }
DELETE /api/v1/real_estate_properties/:id/valuations/:vid

namespace :rentcast do
  GET    /rentcast/configuration        # { api_key_set, configured, quota: {used, limit, period}, last_synced_at }
  PATCH  /rentcast/configuration
  DELETE /rentcast/configuration
  POST   /rentcast/configuration/test
end
```

`POST /real_estate_properties` does address resolution inline (one `/properties` call)
rather than offering a separate preview endpoint — a preview would double the quota cost
of adding a property. If RentCast isn't configured, or can't find the address, the
property is created from the typed address with `sync_enabled: false` and a manual value.

Business logic in `app/domain/**` per AGENTS.md; controllers stay thin. Swagger specs
alongside, as with the other resources.

## Frontend

`frontend/src/pages/investments/RealEstateSection.tsx`, registered in `Investments.tsx`'s
`SECTIONS` between Crypto and Net Worth.

**Section layout**

- Header stats: total value · total mortgage · total equity, with change over the page timeframe.
- Property cards: name, formatted address, current value + change, source badge
  ("RentCast · Jul 21" / "Manual"), equity bar if a mortgage is linked.
- Detail view: value chart, facts strip, mortgage panel, valuation table.

**Chart** (lightweight-charts v5, per the Market redesign)

- Solid line — market value: purchase → sale events → manual → weekly AVM.
- Shaded band — AVM `priceRangeLow`/`priceRangeHigh` around recent points.
- Dimmed stepped line — tax assessed value, its own series, visually subordinate, with a
  legend note that assessed ≠ market.

**Empty / unconfigured states**

- No properties → "Add a property" form: address, optional purchase price + date.
- No RentCast key → inline banner "Connect RentCast to value properties automatically"
  linking to Settings → Integrations, and the value field becomes required on create.
  Everything else in the section works identically.

**Settings → Integrations** — a `rentcast` entry in `apiKeyProviders.tsx` (shared
`ApiKeyProviderDetail` / `ApiKeyCredentialsForm`, plus `RentcastUsage.tsx`) following Tiingo, with `Home` as the lucide icon, a quota bar
(`11 / 50 requests · resets Aug 1`), next scheduled sync, and per-property last-sync status.

Semantic color tokens only, per `frontend/CLAUDE.md`; design guard grep before commit.

## Testing

- **rspec** — current-value precedence (incl. same-day tiebreak and sold properties);
  valuation uniqueness/idempotent re-sync; `Rentcast::Client` against WebMock stubs
  (success, 401, 429, address-not-found); `PropertyRefresher` seeding assessments + sales
  from a fixture payload; quota guard blocking a fan-out that would overrun; `NetWorthHistory`
  real-estate bucket (carry-forward, gross value, mortgage not double-counted); request
  specs for all endpoints.
- **vitest** — section render with/without properties, add-property form, manual-value
  entry, unconfigured-integration banner.
- Sorbet sigs on new services/models; `bin/rubocop`, `bin/brakeman` clean.

## Build order

Each phase is independently shippable.

1. **Manual-only foundation** — migrations, models, valuation precedence, net-worth bucket,
   API, section UI. Fully usable with no API key: add a property, type values, see it in net worth.
2. **RentCast integration** — client, configuration model, settings UI, address resolution
   on create, "Refresh now", history seeding from assessments + sales.
3. **Automation** — weekly job, quota guard, Issues on failure, quota display.

## Resolved during implementation

- **Net-worth metrics** — `Metrics::Definitions::NetWorth` calls `NetWorthHistory` directly,
  so it inherited the real-estate bucket with no change.
- **Test connection costs a request** — RentCast has no free credential-check endpoint, so
  `test_connection!` runs a `/properties?city=Austin&state=TX&limit=1` lookup. City/state
  rather than an address on purpose: it exercises the credentials and nothing else, so a
  failure can't be a geocoding miss on whatever address we happened to pick. The button is
  labelled "Test connection (uses 1 request)" and the detail pane says why.
- **Query encoding is percent, not form** — `URI.encode_www_form` writes spaces as `+`,
  which RentCast's address parser reads literally: every lookup returns 400 "could not be
  parsed or geolocated" despite a valid key. `Rentcast::Client.build_query` percent-encodes
  instead, matching their documented examples. Addresses are also assembled as
  "Street, City, State, Zip" — comma before the zip, per their spec.
- **Same-day tiebreak** — "newest wins" needed a rule for the day a sync and a manual entry
  land together. `RealEstateValuation::SOURCE_RANK` orders manual > rentcast > sale >
  purchase, so a value you type beats that morning's estimate and next week's sync beats it
  back.
- **Sold properties** — `value_breakpoints` appends a zero point the day after `sold_date`
  rather than dropping the property, so the asset falls off cleanly while its history
  survives and the sale proceeds (now sitting in a cash account) aren't double-counted.

## As built

Everything above shipped, plus:

- Swagger docs for all endpoints (`spec/requests/swagger/real_estate_spec.rb`, with
  `RealEstateProperty` / `RealEstateValuation` component schemas).
- Tapioca RBIs for the three new models; `srb tc` reports no errors in any new file.
- Tests: 47 backend examples (model precedence, quota, client against WebMock, refresher
  seeding, budget guard, net-worth bucket, request specs) and 10 frontend integration
  tests, plus a net-worth case asserting gross value and mortgage don't double-count.
