# Frontend — agent guardrails

**Before changing any UI, read [`DESIGN.md`](./DESIGN.md).** It is the source of truth
for Fin's design language. Keep changes visually consistent across all themes.

Stack: React 19 + TypeScript + Vite + Tailwind CSS v4 + Radix. Path alias `@/` → `src/`.

## Non-negotiable rules (full detail in DESIGN.md)

1. **Only semantic tokens for color** — `bg-primary`, `text-foreground`, `bg-card`,
   `border-border`, `text-muted-foreground`, `ring-primary`, etc. **Never** hardcode
   hex/`rgb()`/`style={{color}}` or raw Tailwind palette classes (`bg-blue-500`,
   `text-green-700`). 16 themes depend on this. Exception: `src/components/charts/theme.ts`.
2. **Themes** are `data-theme` on `<html>`. When adding/editing one, update **both**
   `src/index.css` and the `THEMES` array in `src/hooks/useTheme.ts` (and
   `DARK_THEME_IDS` in `charts/theme.ts` if dark). Test light, dark, and Copper (split, default).
3. **Components**: primitives in `src/components/ui/` are **mandatory** — `Button`,
   `Input`/`Select`/`Textarea`/`Checkbox`/`Label`/`Field`, `Dialog`/`Drawer` (Radix),
   `useConfirm()` (never `window.confirm`/`alert` — lint-banned), `toast` (never a
   per-page toast), `Tabs`, `Badge`, `EmptyState`/`ErrorState`/`Skeleton`,
   `PageHeader`/`SectionRailNav`. Author new primitives with `cn()` + an inline
   object-literal variant map — don't add CVA.
4. **Formatting**: use `formatCurrency` / `formatPercent` / `formatDate` from
   `@/lib/utils`. Standard null placeholder is `—`.
5. **Type/size**: font family via `data-font`, size via the rem-based global scale —
   never set fixed `px` font sizes. For small print use `text-caption` /
   `text-tiny` / `text-micro` (11 / 10 / 9px at the default size), not `text-[10px]`.

## Verify before you finish

Grep your diff for hardcoded colors and confirm nothing breaks on dark/split themes:

```bash
# should return nothing in app UI (charts/theme.ts is the only allowed exception).
# Scans .ts too — helpers that return class strings (lib/*.ts) count as UI.
grep -rnE '#[0-9a-fA-F]{3,6}|(bg|text|border|ring)-(blue|green|red|gray|slate|zinc|sky|emerald|amber|neutral|stone|orange|yellow|purple|violet|indigo|teal|cyan|pink|rose|lime|fuchsia)-[0-9]|ring-ring|bg-popover|text-popover|text-\[[0-9]+px\]' src --include='*.tsx' --include='*.ts' | grep -v 'charts/theme' | grep -v 'charts/SankeyChart' | grep -v '\.test\.'
```

## API types are generated

`src/api/schema.d.ts` is generated from `../swagger/v1/swagger.yaml` by `openapi-typescript`
— never edit it by hand. `src/api/types.ts` re-exports those schemas under the app's names
(`export type X = components["schemas"]["X"]`) and keeps hand-written types only for view
models, request payloads, and shapes OpenAPI 3.0 can't express (e.g. `[date, value]` tuples).

When an API response changes: update the rswag spec/schema, regenerate the document from the
repo root with `RAILS_ENV=test bundle exec rake rswag:specs:swaggerize`, then run
`npm run gen:api` here and commit both. `npm run check:api` fails if `schema.d.ts` is stale.

Commands: `npm run dev` · `npm run lint` · `npm test` · `npm run build` · `npm run gen:api` · `npm run check:api`.
