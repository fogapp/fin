# Fin — Design Language

This is the single source of truth for how the Fin frontend looks and how new UI
should be built. It documents the system that **already exists in the code** — read
it before adding or changing any UI so that changes stay visually consistent across
every theme.

Audience: humans and coding agents (Claude Code, etc.). The companion
`frontend/CLAUDE.md` points agents here automatically.

**Source-of-truth files** (this doc describes them; if they change, update this doc):

- `src/index.css` — the `@theme` token block + every `[data-theme]` override. **The tokens live here, not in a separate tokens file.**
- `src/hooks/useTheme.ts` — the `THEMES` registry (must stay in sync with `index.css`).
- `src/components/charts/theme.ts` — chart palette + rules.
- `src/components/ui/` — the primitive component library.
- `src/lib/utils.ts` — `cn()` and the shared formatters.

---

## 1. The cardinal rule

**Style only through semantic tokens. Never hardcode a color.**

Every color in the app resolves through a semantic CSS variable (e.g.
`--color-primary`, `--color-background`) that each theme redefines. Sixteen themes
depend on this. A raw hex, an `rgb()`, or a **raw Tailwind palette class**
(`bg-blue-500`, `text-green-700`, `bg-gray-100`) hard-codes one theme's look and
silently breaks in the other fifteen.

```tsx
// ✅ correct — follows the active theme
<div className="bg-card text-card-foreground border border-border">

// ❌ wrong — frozen to one theme, breaks on dark/split themes
<div className="bg-white text-gray-900 border border-gray-200">
<div style={{ color: "#1a1a1a" }}>
```

The **only** sanctioned raw colors are inside `src/components/charts/theme.ts`, which
is a deliberately curated, contrast-checked chart palette (see §6).

---

## 2. Token reference

Defined in `src/index.css` under `@theme` (the light/default values) and overridden
per theme. Use them as Tailwind utility classes (`bg-*`, `text-*`, `border-*`, `ring-*`).

| Token | Utility examples | Use for |
|---|---|---|
| `background` / `foreground` | `bg-background` `text-foreground` | Page surface + primary text |
| `card` / `card-foreground` | `bg-card` `text-card-foreground` | Card/panel surfaces |
| `muted` / `muted-foreground` | `bg-muted` `text-muted-foreground` | Recessive surfaces, secondary/label text |
| `border` | `border-border` | All hairlines and dividers |
| `input` | `border-input` | Form control borders |
| `primary` / `primary-foreground` | `bg-primary` `text-primary` `ring-primary` | Brand action color, focus rings, links |
| `secondary` / `secondary-foreground` | `bg-secondary` | Low-emphasis fills |
| `accent` / `accent-foreground` | `hover:bg-accent` | Hover/active states |
| `destructive` / `destructive-foreground` | `bg-destructive` | Delete/danger actions |
| `positive` | `text-positive` `bg-positive/10` | Gains, affirmative/success green, "configured" states |
| `negative` | `text-negative` `bg-negative/10` | Losses, errors |
| `warning` | `text-warning` `bg-warning/10` | Warnings, stale data, partial states |

`positive` / `negative` / `warning` are re-declared brighter for dark-surfaced themes
in `index.css` (the `[data-theme="dark"], …` block — keep that list in sync with
`DARK_THEME_IDS`). Use opacity modifiers (`bg-positive/10`, `border-warning/30`) for
subtle tints; the solid token for dots, bars, and icons.

Radius: `--radius-lg` = `0.5rem`. Convention in the primitives:

- `rounded-lg` — buttons, inputs (default control radius).
- `rounded-xl` — cards.
- `rounded-full` — badges, avatars, pills.

Elevation is intentionally flat: cards use `shadow-sm` only. Don't reach for heavier shadows.

---

## 3. Themes

The active theme is the `data-theme` attribute on `<html>`, set pre-paint in
`index.html` and by `useTheme()`. `light` is represented by an empty attribute
(the `@theme` defaults). All others are `[data-theme="<id>"]` blocks in `index.css`.

Sixteen themes in three structural types (see the `type` field in `useTheme.ts`):

- **light** — light background, light sidebar. `light, sand, forest, rose, ocean, lavender, mint`
- **dark** — dark background, dark sidebar. `dark, midnight, dusk, slate, ember`
- **split** — light content area with a **dark sidebar**. `eclipse, sage, plum, copper` (Copper is the default). Split themes add a `[data-theme="x"] [data-sidebar] { … }` block that re-declares the tokens for anything inside the element carrying `data-sidebar`.

Because the sidebar is themed by overriding the same tokens inside `[data-sidebar]`,
sidebar components must use the **same** semantic tokens as everything else
(`bg-card`, `text-foreground`, …) — never hardcode a "dark sidebar" color. That's
what makes one component render correctly in both light and split themes.

### Adding or editing a theme (checklist)

1. Add the full `[data-theme="<id>"] { … }` block to `src/index.css` with **every**
   token (copy an existing block of the same type so none are missing — a missing
   token falls back to the light default and looks broken).
2. If it's a **split** theme, also add the `[data-theme="<id>"] [data-sidebar] { … }` block.
3. Register it in the `THEMES` array **and** the `ThemeId` union in
   `src/hooks/useTheme.ts` (id, label, type, preview colors; `sidebarBg` for split).
4. If the theme is dark-surfaced, add its id to `DARK_THEME_IDS` in
   `src/components/charts/theme.ts` so charts switch to the dark palette.
5. Verify by switching to it in the UI and checking a card, the sidebar, a form, and a chart.

`index.css` and `useTheme.ts` are two hand-maintained lists of the same themes —
they must always agree. This duplication is the most common drift point; check both.

---

## 4. Typography

- **Family** is swappable via `data-font` on `<html>`. Valid values (registered in
  `src/hooks/useFont.ts`, mapped to `--font-sans` in `index.css`, self-hosted as
  `public/fonts/*.woff2` via `public/fonts.css`): `system, inter, dm-sans, nunito`
  (default), `ibm-plex, outfit`. Body inherits `--font-sans`. Adding a family means
  touching all of those plus the preload map in `index.html`.
- **Size** is a global scale set as the root `font-size` (rem-based, `FONT_SIZES` in
  `src/hooks/useFontSize.ts`), keyed
  `xs 13px / sm 14px (default) / md 16px / lg 18px / xl 20px`. Because it's rem-based,
  size components with Tailwind's `text-*` / spacing scale and they scale together —
  don't set fixed `px` font sizes on components. Small print has its own tokens in
  `index.css`: `text-caption` / `text-tiny` / `text-micro` (11 / 10 / 9px at the default
  size) for captions, badges and uppercase eyebrow labels.
- Weight scale in use: `font-medium` for controls/labels, `font-semibold`/`font-bold`
  for headings. Card titles are deliberately quiet: `text-sm font-medium text-muted-foreground`.

---

## 5. Components

**Location.** Reusable primitives live in `src/components/ui/`
(`button, card, badge, input, select, textarea, checkbox, label, field, skeleton,
dialog, drawer, form-dialog, confirm, toast, tabs, empty-state, dropdown-menu, popover,
tooltip, pagination, key-value-table`). Feature components live one level
up in `src/components/` and its subfolders (`charts/`, `layout/`, `holdings/`,
`market/`, `filter-bar/`, `transaction/`, `import/`, `spend-chart/`). Layout scaffolding (`AppShell`, `Sidebar`, `PageHeader`,
`SectionRailNav`, `MobileNav`) is in `src/components/layout/`.

**The primitive layer is mandatory, not optional.** Every one of these concerns has
exactly one implementation — reach for it instead of hand-rolling:

| Concern | Primitive | Rules |
|---|---|---|
| Buttons | `ui/button` | Sizes `xs/sm/md/lg/icon/icon-sm`. Never a raw styled `<button>`. |
| Modals | `ui/dialog` | Radix-based: portal, focus trap, scroll lock, Esc, `aria-modal` built in. |
| Side sheets | `ui/drawer` | Overlay drawers only; the in-flow split-view panel (TransactionTable) is a separate deliberate pattern. |
| Destructive confirms | `ui/confirm` → `useConfirm()` | `window.confirm`/`alert` are banned (lint-enforced). |
| Transient feedback | `ui/toast` → `toast.success/error/info` | One `<Toaster/>` in App.tsx; never a per-page toast. Mutations without a local `onError` auto-toast via the global MutationCache handler. |
| Form fields | `ui/input`, `ui/select`, `ui/textarea`, `ui/checkbox`, `ui/label`, `ui/field` | Every input has a `Label`/`aria-label`; field errors render via `FieldError`. |
| Tabs / segmented controls | `ui/tabs` | One active-state language: primary-tinted pill. |
| Dropdown menus | `ui/dropdown-menu` | Radix-based; for a list of actions (chart export, household switcher). Content is `rounded-lg border bg-card shadow-md`; `destructive` prop on items for delete actions. |
| Popovers | `ui/popover` | Radix-based; for panels holding more than actions — a form, a date range, a checklist (notification bell, custom timeframe, table options, `SavedItemsMenu`). Same surface as dropdown menus. Never hand-roll an `absolute` panel with an outside-click listener. |
| Pagination | `ui/pagination` | `variant="range"` for client-paged rows (with `usePagination`), `variant="simple"` for server-paged lists. |
| Tooltips | `ui/tooltip` | Radix-based; wrap a cluster in one `TooltipProvider` (150ms delay, skip-delay between triggers); prefer over native `title` for icon-only controls. |
| Section rails | `layout/SectionRailNav` | The Cashflow/Investments/Settings vertical rail. |
| Page headers | `layout/PageHeader` | `level=1` (text-xl) for routed top-level pages, `level=2` (text-base) for panes/sections; `back={{to}}` on detail pages; `subtitle` for the muted line. Discrete header buttons go in `actions` (the pencil menu in the shared cluster: actions → household switcher → bell → avatar); `children` is only for stateful inline controls (steppers, selects, a form's primary submit). |
| Empty / error / loading | `ui/empty-state`, `PageState`'s `ErrorState` (takes `onRetry`), `ui/skeleton` | Never swallow `isError` into an empty list; never `return null` for a failed section. |

**Button-row order:** Cancel/secondary on the left, the primary action on the right —
in modal footers, drawer footers, and inline editors alike. Labels are sentence case.

**Money coloring:** use `moneyColor(value)` from `lib/utils` (`text-positive` /
`text-negative`, zero unstyled). `text-destructive` is for validation errors and
dangerous actions; `text-negative` is for financial losses and failing statuses.

**Authoring pattern.** Primitives are plain function components that compose classes
with `cn()` (clsx + tailwind-merge) and select variants via an **inline object-literal
map** keyed on a `variant`/`size` prop. Match this pattern — for example:

```tsx
import { cn } from "@/lib/utils";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "default" | "outline" | "ghost" | "destructive";
  size?: "sm" | "md" | "lg";
}

export function Button({ className, variant = "default", size = "md", ...props }: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-lg font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:pointer-events-none disabled:opacity-50",
        { default: "bg-primary text-primary-foreground hover:bg-primary/90",
          outline: "border border-border bg-background hover:bg-accent",
          ghost: "hover:bg-accent hover:text-accent-foreground",
          destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90" }[variant],
        { sm: "h-8 px-3 text-xs", md: "h-9 px-4 text-sm", lg: "h-10 px-6 text-sm" }[size],
        className,
      )}
      {...props}
    />
  );
}
```

- Always spread `className` last through `cn()` so callers can override.
- Interactive/overlay primitives (dialogs, dropdowns, tooltips, separators) are built
  on **Radix** (`@radix-ui/react-*`). Reach for the installed Radix primitive before
  hand-rolling focus/keyboard/portal behavior.
- Control heights: `h-7` (xs) / `h-8` (sm) / `h-9` (md, default) / `h-10` (lg). Inputs are `h-9`.
- Focus is always `focus-visible:ring-2 focus-visible:ring-primary` — keep it consistent.
  There is **no `--color-ring` token**; `ring-ring` is a dead utility in Tailwind v4 and
  is banned (the guard grep catches it). Use `ring-primary`, and `focus-visible:`, not `focus:`.
- Note: `class-variance-authority` is not a dependency; the inline-map pattern above is
  the convention. Don't introduce CVA for one component — either follow the existing
  pattern or migrate the whole `ui/` folder deliberately.

**Layering.** Four bands, and nothing invents a fifth:

| Band | Range | What lives there |
|---|---|---|
| Page content | `z-10` – `z-20` | A page's own sticky chrome: table filter bars, bulk bars, `<thead>`, sticky first columns. |
| App chrome | `z-30` | The sticky `PageHeader` and `MobileNav` — always above a page's own content. |
| Overlays | `z-40` – `z-50` | Dialog/drawer/command-palette backdrops (`z-40`) and their panels, tooltips and menus (`z-50`). |
| Toasts | `z-[60]` | The one `<Toaster/>`, above everything. |

The trap: **a positioned element with a z-index is a stacking context**, so a panel
inside it can never escape its parent's band however high its own z-index is. The sticky
`PageHeader` is exactly that — the notification panel and household switcher render at
`z-50` *inside* it, so they sit wherever the header sits. When the header was `z-10`, the
transactions table's `z-20` filter bar painted straight over an open notification panel.
Anything that must clear the header's band belongs in a portal (Radix `DropdownMenu`,
`Popover`, `Dialog` and `Tooltip` already do this), not on a bigger number.

**Formatting.** Use the shared helpers in `src/lib/utils.ts` — `formatCurrency`,
`formatPercent`, `formatDate`, `formatMonthLabel` — instead of re-implementing number/date
formatting (they encode the app's timezone and locale rules). `—` is the app's standard
em-dash placeholder for null/empty values.

---

## 6. Charts

Charts are the **one** place with their own literal palette, in
`src/components/charts/theme.ts`. Rules that must be preserved:

- The categorical palette (`LIGHT_SERIES` / `DARK_SERIES`, 8 slots) is CVD-safe and
  contrast-checked. **Slots are assigned by fixed series order and never cycled** — a
  9th+ series folds into the neutral "Other" gray. Don't add colors or cycle the palette.
- **Color follows the entity, not its rank.** Use `assignSeriesColors(names, theme)` to
  build one entity→color map and share it across every panel and any colored list dots on
  the same page, so filtering series never repaints the survivors.
- Get the active palette with `useChartTheme()`; it live-switches light/dark by watching
  `data-theme`. Which themes count as dark is `DARK_THEME_IDS` — keep it in sync when
  adding dark themes (see §3, step 4).
- Diverging values (e.g. net cashflow) use `theme.positive` / `theme.negative` /
  `theme.neutral`, not palette slots.
- Chart surfaces (`surface`) reference `var(--color-card)` so charts sit on the themed card.
- **Canvas charts (lightweight-charts)**: the Market pages' financial charts render to
  canvas and can't use CSS classes. `components/market/lwcTheme.ts` reads the live
  semantic tokens (`--color-positive`, `--color-border`, …) off the root element and
  re-reads on `data-theme` changes, so canvas charts follow all themes without their
  own palette. The only literals are `CANVAS_TOKEN_FALLBACKS` in `charts/theme.ts`
  (SSR/jsdom fallbacks — part of the sanctioned exception file). Up/down candle colors
  come from the `positive`/`negative` tokens; indicator overlays use the categorical
  palette slots via `useChartTheme()`.

---

## 7. Do / Don't quick reference

**Do**

- Use semantic token utilities for every color (`bg-primary`, `text-muted-foreground`, `border-border`).
- Build variants with the `cn()` + inline-map pattern; override via a trailing `className`.
- Use Radix primitives for overlays and interactive widgets.
- Use `formatCurrency` / `formatPercent` / `formatDate` from `lib/utils`.
- When touching themes, edit `index.css` **and** `useTheme.ts` together.

**Don't**

- Hardcode hex/`rgb()`/`style={{color}}` or raw Tailwind palette classes (`bg-blue-500`, `text-green-700`) in app UI — including `.ts` helpers that return class strings.
- Assume light-mode contrast — check dark and split (Copper) themes.
- Give the sidebar its own hardcoded dark colors; use the shared tokens inside `data-sidebar`.
- Add or cycle chart colors, or key chart color to rank instead of entity.
- Set fixed `px` font sizes (breaks the global size scale).
- Use `window.confirm`/`alert` (lint-banned) — `useConfirm()` and `toast` exist.
- Hand-roll a modal/drawer with `fixed inset-0` divs — use `ui/dialog`/`ui/drawer`.
- Write `ring-ring` or `focus:ring-*` — the ring token doesn't exist; use `focus-visible:ring-2 focus-visible:ring-primary`.
- Re-implement a primary button (`bg-primary … hover:bg-primary/90`) inline — use `<Button>`.
- Swallow query errors into `data = []` defaults or `return null` — surface `ErrorState`.

---

## 8. Known inconsistencies to reconcile

- **✅ Resolved — gain/loss + warning colors are now tokens** (migrated ~60 sites; keep
  new UI on `positive`/`negative`/`warning`).
- **✅ Resolved (2026-07-06) — consistency overhaul.** Full audit + remediation:
  the primitive layer was completed (dialog/drawer/confirm/
  toast/select/textarea/checkbox/label/field/tabs/empty-state, SectionRailNav, PageHeader
  back/subtitle, Button xs/icon sizes), all hand-rolled modals moved to Radix,
  `window.confirm`/`alert` eliminated, silent query/mutation failures now surface via
  `ErrorState` + the global mutation-error toast, and the broken `ring-ring` focus classes
  were replaced with `ring-primary`. §5's primitive table is now the contract.
- **✅ Resolved (2026-09-25) — hand-rolled dropdown panels.** The notification bell,
  household switcher, `ChartCard` export menu, `TimeframeSelector` custom range,
  `HoldingsTable` options and the saved views/reports panels (now one `SavedItemsMenu`)
  were `absolute` panels with ad hoc z-indexes and document outside-click listeners, and
  none closed on Escape. They are portaled `ui/dropdown-menu` / `ui/popover` now; keep new
  panels on those primitives (§5).
- **`charts/` uses literal colors by design** — `charts/theme.ts` (the curated palette) and
  a couple of chart-internal grid strokes (e.g. `SankeyChart.tsx`) are the sanctioned
  exceptions and are excluded from the guard grep.
- **`bg-black/40` overlay backdrops and `bg-white` switch knobs** are accepted literals
  (uniform across themes by design); everything else goes through tokens.

---

## 9. Design-change workflow

The intended loop for evolving the design:

1. **Mock it up.** Prototype the new component/screen/theme visually and iterate on look-and-feel.
2. **Encode the decision here.** Land new tokens in `index.css` (+ `useTheme.ts` for themes),
   and update the relevant section of this doc — values in code, rationale in prose.
3. **Implement with Claude Code.** It reads `frontend/CLAUDE.md` → this doc, and builds
   against the tokens/conventions instead of inventing styling.
4. **Review against §7.** Before merging UI, check the diff for hardcoded colors and
   cross-theme breakage (a quick pass in dark + Copper).
