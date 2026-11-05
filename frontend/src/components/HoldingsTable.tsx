import { useState, useRef, useMemo, Fragment } from "react";
import { useNavigate } from "react-router-dom";
import { Search, SlidersHorizontal, X, RefreshCw, ChevronUp, ChevronDown, ChevronRight } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { formatCurrency, cn, moneyColor } from "@/lib/utils";
import { COLUMN_LABELS, FILTER_FIELD_LABELS, holdingDisplayName, holdingSubtitle } from "./holdings/types";
import type { ActiveFilter, GroupBy, HoldingColumn, HoldingRow, SortDir, SortField } from "./holdings/types";
import { HoldingsOptionsPanel } from "./holdings/HoldingsOptionsPanel";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { HoldingDrawer } from "./holdings/HoldingDrawer";
import { useHashParam } from "@/hooks/useHashParam";
import { ExportToOfficeButton } from "@/components/ExportToOfficeButton";
import type { OfficeDataset } from "@/api/types";
import { useElementHeight } from "@/hooks/useElementHeight";

export type { HoldingRow, HoldingColumn } from "./holdings/types";

interface Props {
  holdings: HoldingRow[];
  isLoading?: boolean;
  columns?: HoldingColumn[];
  onRefresh?: () => void;
  isRefreshing?: boolean;
  /** Which Office dataset this table's rows come from — `portfolio` for the
   *  consolidated view, `holdings` for an account's own positions. Omitted
   *  where no dataset matches (the crypto section's synthesized rows), which
   *  simply leaves the export off that table. */
  exportDataset?: OfficeDataset;
  /** Extra server-side scope for the export, e.g. the account being viewed. */
  exportScope?: Record<string, string | number | undefined>;
}

// ── Constants ─────────────────────────────────────────────────────────────────

const DEFAULT_COLUMNS: HoldingColumn[] = [
  "ticker", "quantity", "price", "market_value", "cost_basis", "unrealized_gl", "unrealized_gl_pct",
];

// Columns that right-align
const RIGHT_ALIGN: Set<HoldingColumn> = new Set([
  "quantity", "price", "market_value", "cost_basis",
  "unrealized_gl", "unrealized_gl_pct", "est_annual_income", "dividend_yield",
]);

// Rows mounted before the "Show all" expander — large portfolios were
// rendering thousands of <tr> at once on first paint.
const ROW_CAP = 100;

// ── Filter logic ──────────────────────────────────────────────────────────────

function applyFilter(h: HoldingRow, f: ActiveFilter): boolean {
  const num = (v: number | null) => v ?? 0;
  switch (f.field) {
    case "market_value":      return applyNumeric(num(h.market_value), f);
    case "unrealized_gl":     return applyNumeric(num(h.unrealized_gl), f);
    case "unrealized_gl_pct": return applyNumeric(num(h.unrealized_gl_pct), f);
    case "quantity":          return applyNumeric(num(h.quantity), f);
    case "asset_class":
      if (f.operator === "blank")   return !h.asset_class;
      if (f.operator === "present") return !!h.asset_class;
      return (h.asset_class ?? "").toLowerCase() === f.value.toLowerCase();
    default: return true;
  }
}

function applyNumeric(val: number, f: ActiveFilter): boolean {
  const n = parseFloat(f.value);
  if (f.operator === "blank")   return val === 0;
  if (f.operator === "present") return val !== 0;
  if (isNaN(n)) return true;
  if (f.operator === "gt")     return val > n;
  if (f.operator === "lt")     return val < n;
  if (f.operator === "equals") return val === n;
  return true;
}

/** G/L tint. Unlike plain `moneyColor`, a zero G/L reads as a (green) gain —
 * the table prints it as "+$0.00", so the color must match the sign. */
function glColor(val: number) {
  return moneyColor(val) || "text-positive";
}

// ── Sorting ───────────────────────────────────────────────────────────────────

function getValue(h: HoldingRow, field: SortField): number | string {
  switch (field) {
    // Sort by what the column actually prints, so a labelled holding files
    // under its label rather than under a ticker nobody can see.
    case "ticker":            return (holdingDisplayName(h) ?? "").toLowerCase();
    case "quantity":          return h.quantity;
    case "price":             return h.price;
    case "market_value":      return h.market_value;
    case "cost_basis":        return h.cost_basis ?? 0;
    case "unrealized_gl":     return h.unrealized_gl;
    case "unrealized_gl_pct": return h.unrealized_gl_pct;
    case "est_annual_income": return h.est_annual_income ?? 0;
    case "dividend_yield":    return h.dividend_yield ?? 0;
    case "asset_class":       return (h.asset_class ?? "").toLowerCase();
    default:                  return 0;
  }
}

function sortHoldings(items: HoldingRow[], field: SortField, dir: SortDir): HoldingRow[] {
  return [...items].sort((a, b) => {
    const va = getValue(a, field);
    const vb = getValue(b, field);
    const cmp = typeof va === "string" ? va.localeCompare(vb as string) : (va as number) - (vb as number);
    return dir === "asc" ? cmp : -cmp;
  });
}

// ── Main component ────────────────────────────────────────────────────────────

export function HoldingsTable({ holdings, isLoading, columns: columnsProp, onRefresh, isRefreshing, exportDataset, exportScope }: Props) {
  const navigate = useNavigate();

  const [search, setSearch]             = useState("");
  const [searchOpen, setSearchOpen]     = useState(false);
  const [sortField, setSortField]       = useState<SortField>("market_value");
  const [sortDir, setSortDir]           = useState<SortDir>("desc");
  const [groupBy, setGroupBy]           = useState<GroupBy>("none");
  const [visibleCols, setVisibleCols]   = useState<HoldingColumn[]>(columnsProp ?? DEFAULT_COLUMNS);
  const [filters, setFilters]           = useState<ActiveFilter[]>([]);
  const [optionsOpen, setOptionsOpen]   = useState(false);
  const [filterCounter, setFilterCounter] = useState(0);
  const filterBarRef = useRef<HTMLDivElement>(null);
  const filterBarHeight = useElementHeight(filterBarRef, 41);
  // Selected row lives in the URL hash, like the transaction drawer.
  const [selectedId, setSelectedId] = useHashParam("hid", { replace: true });


  // ── Filter & sort ───────────────────────────────────────────────────────────

  const q = search.trim().toLowerCase();

  const displayed = useMemo(() => {
    let rows = holdings;

    const terms = q ? q.split(/\s+/) : [];
    if (terms.length) {
      rows = rows.filter((h) => {
        const haystack = `${h.label ?? ""} ${h.ticker ?? ""} ${h.name ?? ""}`.toLowerCase();
        return terms.every((t) => haystack.includes(t));
      });
    }

    for (const f of filters) {
      rows = rows.filter((h) => applyFilter(h, f));
    }

    return sortHoldings(rows, sortField, sortDir);
  }, [holdings, q, filters, sortField, sortDir]);

  const groups = useMemo<{ label: string; rows: HoldingRow[] }[]>(() => {
    if (groupBy === "none") return [{ label: "", rows: displayed }];
    const map = new Map<string, HoldingRow[]>();
    for (const h of displayed) {
      const key = h.asset_class ?? "Unknown";
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(h);
    }
    return Array.from(map.entries())
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([label, rows]) => ({ label, rows }));
  }, [displayed, groupBy]);

  const [showAll, setShowAll] = useState(false);
  // Cap mounted rows across groups; group headers keep the full count so
  // truncation stays visible. Default sort is market_value desc, so the cap
  // surfaces the largest positions.
  const visibleGroups = useMemo<{ label: string; rows: HoldingRow[]; total: number }[]>(() => {
    if (showAll || displayed.length <= ROW_CAP) {
      return groups.map((g) => ({ ...g, total: g.rows.length }));
    }
    let remaining = ROW_CAP;
    const out: { label: string; rows: HoldingRow[]; total: number }[] = [];
    for (const g of groups) {
      if (remaining <= 0) break;
      const rows = g.rows.slice(0, remaining);
      remaining -= rows.length;
      out.push({ label: g.label, rows, total: g.rows.length });
    }
    return out;
  }, [groups, displayed.length, showAll]);
  const hiddenCount = showAll ? 0 : Math.max(0, displayed.length - ROW_CAP);

  // ── Column sort toggle ──────────────────────────────────────────────────────

  function handleHeaderClick(col: HoldingColumn) {
    if (col === sortField) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortField(col);
      setSortDir("desc");
    }
  }

  function addFilter() {
    setFilters((prev) => [
      ...prev,
      { id: filterCounter, field: "market_value", operator: "gt", value: "" },
    ]);
    setFilterCounter((n) => n + 1);
  }

  function updateFilter(id: number, patch: Partial<ActiveFilter>) {
    setFilters((prev) => prev.map((f) => (f.id === id ? { ...f, ...patch } : f)));
  }

  function removeFilter(id: number) {
    setFilters((prev) => prev.filter((f) => f.id !== id));
  }

  const colCount = visibleCols.length;
  const activeFilterCount = filters.length + (q ? 1 : 0);

  // Drawer navigation walks the mounted rows in display order.
  const mounted = useMemo(() => visibleGroups.flatMap((g) => g.rows), [visibleGroups]);
  const selectedIndex = selectedId ? mounted.findIndex((h) => h.id === selectedId) : -1;
  const selected = selectedIndex >= 0 ? mounted[selectedIndex] : null;
  const step = (i: number) => (mounted[i] ? () => setSelectedId(mounted[i].id) : undefined);

  // ── Render ──────────────────────────────────────────────────────────────────

  return (
    <div className="flex min-h-0 bg-card">
    <div className="flex min-w-0 flex-1 flex-col bg-card text-sm">
      {/* Filter bar — sticky so it stays visible while scrolling */}
      <div ref={filterBarRef} className="sticky top-0 z-20 flex items-center gap-1.5 border-b bg-card px-3 py-2">
        {/* Search */}
        <div className={cn("flex items-center gap-1.5 transition-all overflow-hidden", searchOpen ? "flex-1" : "")}>
          {searchOpen ? (
            <div className="relative flex-1">
              <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none" />
              <Input
                autoFocus
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search ticker or name…"
                aria-label="Search ticker or name"
                className="h-7 pl-8 pr-7"
              />
              <button
                onClick={() => { setSearch(""); setSearchOpen(false); }}
                aria-label="Clear search"
                className="absolute right-2 top-1/2 -translate-y-1/2 rounded text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <X size={12} />
              </button>
            </div>
          ) : (
            <Button
              variant="ghost"
              size="xs"
              onClick={() => setSearchOpen(true)}
              className="gap-1.5 px-2 text-muted-foreground hover:text-foreground"
            >
              <Search size={13} />
              Search
            </Button>
          )}
        </div>

        {/* Active filter chips */}
        {!searchOpen && filters.map((f) => (
          <span key={f.id} className="flex items-center gap-1 rounded-full border bg-muted/50 px-2 py-0.5 text-xs">
            {FILTER_FIELD_LABELS[f.field]} {f.operator === "gt" ? ">" : f.operator === "lt" ? "<" : f.operator === "equals" ? "=" : f.operator}
            {f.value ? ` ${f.value}` : ""}
            <button
              onClick={() => removeFilter(f.id)}
              aria-label="Remove filter"
              className="ml-0.5 rounded hover:text-destructive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <X size={10} />
            </button>
          </span>
        ))}

        <div className="flex-1" />

        {/* Refresh */}
        {onRefresh && (
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onRefresh}
            disabled={isRefreshing}
            className="text-muted-foreground hover:text-foreground"
            title="Refresh holdings"
            aria-label="Refresh holdings"
          >
            <RefreshCw size={13} className={isRefreshing ? "animate-spin" : ""} />
          </Button>
        )}

        {/* The positions as a spreadsheet in Office — built server-side from
            the same data the table is showing, not from the loaded rows. */}
        {exportDataset && <ExportToOfficeButton dataset={exportDataset} filters={exportScope} />}

        {/* Options */}
        <Popover open={optionsOpen} onOpenChange={setOptionsOpen}>
          <PopoverTrigger asChild>
            <Button
              variant="ghost"
              size="xs"
              aria-label="Table options"
              className={cn(
                "gap-1.5 px-2",
                optionsOpen || activeFilterCount > 0
                  ? "bg-primary/10 text-primary hover:bg-primary/10 hover:text-primary"
                  : "text-muted-foreground hover:text-foreground"
              )}
            >
              <SlidersHorizontal size={13} />
              {activeFilterCount > 0 && (
                <Badge className="bg-primary px-1.5 py-0 text-primary-foreground">
                  {activeFilterCount}
                </Badge>
              )}
            </Button>
          </PopoverTrigger>

          <PopoverContent className="w-72 p-0" aria-label="Table options">
            <HoldingsOptionsPanel
              groupBy={groupBy}
              setGroupBy={setGroupBy}
              sortField={sortField}
              setSortField={setSortField}
              sortDir={sortDir}
              setSortDir={setSortDir}
              visibleCols={visibleCols}
              setVisibleCols={setVisibleCols}
              filters={filters}
              addFilter={addFilter}
              updateFilter={updateFilter}
              removeFilter={removeFilter}
            />
          </PopoverContent>
        </Popover>
      </div>

      {/* Table */}
      <table className="w-full text-sm">
        <thead className="sticky z-10 bg-card" style={{ top: filterBarHeight }}>
          <tr className="border-b text-xs text-muted-foreground">
            {visibleCols.map((col) => {
              const isActive = sortField === col;
              const right = RIGHT_ALIGN.has(col);
              return (
                <th
                  key={col}
                  onClick={() => handleHeaderClick(col)}
                  className={cn(
                    "cursor-pointer select-none px-4 py-2.5 font-medium hover:text-foreground transition-colors",
                    right ? "text-right" : "text-left",
                    isActive && "text-foreground"
                  )}
                >
                  <span className="inline-flex items-center gap-1">
                    {right && isActive && (sortDir === "asc" ? <ChevronUp size={10} /> : <ChevronDown size={10} />)}
                    {COLUMN_LABELS[col]}
                    {!right && isActive && (sortDir === "asc" ? <ChevronUp size={10} /> : <ChevronDown size={10} />)}
                  </span>
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody className="divide-y">
          {isLoading && (
            Array.from({ length: 6 }).map((_, i) => (
              <tr key={i} className="animate-pulse">
                {visibleCols.map((col) => (
                  <td key={col} className="px-4 py-3">
                    <div className="h-4 rounded bg-muted" style={{ width: RIGHT_ALIGN.has(col) ? "60%" : "80%", marginLeft: RIGHT_ALIGN.has(col) ? "auto" : undefined }} />
                  </td>
                ))}
              </tr>
            ))
          )}

          {!isLoading && displayed.length === 0 && (
            <tr>
              <td colSpan={colCount} className="p-0">
                <EmptyState
                  title={q || filters.length ? "No holdings match the current filters." : "No holdings found."}
                />
              </td>
            </tr>
          )}

          {!isLoading && visibleGroups.map(({ label, rows, total }) => (
            <Fragment key={label || "__ungrouped__"}>
              {label && (
                <tr className="bg-muted/30">
                  <td colSpan={colCount} className="px-4 py-1.5 text-xs font-semibold text-muted-foreground">
                    {label}
                    <span className="ml-2 font-normal">({total})</span>
                  </td>
                </tr>
              )}
              {rows.map((h) => (
                <HoldingRowComponent
                  key={h.id}
                  holding={h}
                  columns={visibleCols}
                  isSelected={h.id === selectedId}
                  onSelect={() => setSelectedId(h.id === selectedId ? null : h.id)}
                  onNavigate={(ticker) => navigate(`/market/${ticker}`)}
                />
              ))}
            </Fragment>
          ))}

          {!isLoading && hiddenCount > 0 && (
            <tr>
              <td colSpan={colCount} className="p-2 text-center">
                <Button variant="ghost" size="xs" onClick={() => setShowAll(true)} className="text-muted-foreground hover:text-foreground">
                  Show all {displayed.length.toLocaleString()} positions ({hiddenCount.toLocaleString()} more)
                </Button>
              </td>
            </tr>
          )}
        </tbody>
      </table>

      {/* Footer count */}
      {!isLoading && displayed.length > 0 && (
        <div className="border-t px-4 py-2 text-right text-xs text-muted-foreground">
          {displayed.length} {displayed.length === 1 ? "position" : "positions"}
          {displayed.length !== holdings.length && ` (${holdings.length} total)`}
        </div>
      )}
    </div>{/* end table column */}

      {/* Sliding detail panel */}
      <div
        className={cn(
          "sticky top-0 h-screen flex-shrink-0 self-start overflow-y-auto border-l transition-[width] duration-200",
          selected ? "w-80" : "w-0"
        )}
      >
        {selected && (
          <HoldingDrawer
            holding={selected}
            headerHeight={filterBarHeight}
            onClose={() => setSelectedId(null)}
            onPrev={step(selectedIndex - 1)}
            onNext={step(selectedIndex + 1)}
            onFirst={step(0)}
            onLast={step(mounted.length - 1)}
          />
        )}
      </div>
    </div>
  );
}

// ── Row ───────────────────────────────────────────────────────────────────────

function HoldingRowComponent({
  holding: h,
  columns,
  isSelected,
  onSelect,
  onNavigate,
}: {
  holding: HoldingRow;
  columns: HoldingColumn[];
  isSelected: boolean;
  onSelect: () => void;
  onNavigate: (ticker: string) => void;
}) {
  function cell(col: HoldingColumn) {
    const right = RIGHT_ALIGN.has(col);
    const cls = cn("px-4 py-2.5", right && "text-right tabular-nums");

    switch (col) {
      case "ticker": {
        // Label wins over ticker over description; the ticker link survives as
        // the primary text only when it's what we're printing.
        const primary  = holdingDisplayName(h);
        const subtitle = holdingSubtitle(h);
        return (
          <td key={col} className="px-4 py-2.5">
            {h.ticker && primary === h.ticker ? (
              <button
                onClick={(e) => { e.stopPropagation(); onNavigate(h.ticker!); }}
                className="group flex items-center gap-1 rounded text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <span className="font-medium group-hover:underline">{h.ticker}</span>
                <ChevronRight size={12} className="opacity-0 group-hover:opacity-50" />
              </button>
            ) : (
              <span className="block max-w-40 truncate font-medium">{primary ?? "—"}</span>
            )}
            {subtitle && (
              <p className="max-w-36 truncate text-xs text-muted-foreground">{subtitle}</p>
            )}
          </td>
        );
      }
      case "quantity":
        return <td key={col} className={cls}>{h.quantity.toLocaleString(undefined, { maximumFractionDigits: 8 })}</td>;
      case "price":
        return <td key={col} className={cls}>{formatCurrency(h.price)}</td>;
      case "market_value":
        return <td key={col} className={cn(cls, "font-medium")}>{formatCurrency(h.market_value)}</td>;
      case "cost_basis":
        return <td key={col} className={cn(cls, "text-muted-foreground")}>{h.cost_basis != null ? formatCurrency(h.cost_basis) : "—"}</td>;
      case "unrealized_gl": {
        const pos = h.unrealized_gl >= 0;
        return (
          <td key={col} className={cn(cls, "font-medium", glColor(h.unrealized_gl))}>
            {pos ? "+" : ""}{formatCurrency(h.unrealized_gl)}
          </td>
        );
      }
      case "unrealized_gl_pct": {
        const pos = h.unrealized_gl_pct >= 0;
        return (
          <td key={col} className={cn(cls, glColor(h.unrealized_gl_pct))}>
            {pos ? "+" : ""}{h.unrealized_gl_pct.toFixed(2)}%
          </td>
        );
      }
      case "est_annual_income":
        return <td key={col} className={cls}>{h.est_annual_income != null ? formatCurrency(h.est_annual_income) : "—"}</td>;
      case "dividend_yield":
        return <td key={col} className={cls}>{h.dividend_yield != null ? `${h.dividend_yield.toFixed(2)}%` : "—"}</td>;
      case "asset_class":
        return <td key={col} className="px-4 py-2.5 text-muted-foreground">{h.asset_class ?? "—"}</td>;
      default:
        return <td key={col} />;
    }
  }

  return (
    <tr
      onClick={onSelect}
      className={cn("cursor-pointer transition-colors", isSelected ? "bg-primary/8" : "hover:bg-muted/40")}
    >
      {columns.map((col) => cell(col))}
    </tr>
  );
}
