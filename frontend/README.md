# Fin frontend

The React SPA for Fin: React 19 + TypeScript + Vite + Tailwind CSS v4 + Radix. It talks to
the Rails API over `/api`; in development the Vite server proxies `/api` and `/api-docs` to
the backend (see `vite.config.ts`).

Before changing any UI, read [`DESIGN.md`](./DESIGN.md) (the design language) and
[`CLAUDE.md`](./CLAUDE.md) (the non-negotiable rules and the hardcoded-color guard grep).

## Commands

```bash
npm install
npm run dev         # Vite dev server on http://localhost:5173
npm test            # Vitest
npm run lint        # ESLint
npm run build       # type-check + production build
npm run gen:api     # regenerate src/api/schema.d.ts from ../swagger/v1/swagger.yaml
npm run check:api   # fail if src/api/schema.d.ts is stale
```

The usual way to run the whole app (database, API, worker and this dev server) is
`docker compose up` from the repo root; see the root `README.md` and `INSTALL.md`.
