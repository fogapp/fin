import { useState, useMemo, useEffect, useRef, useCallback, memo } from "react";
import { ChevronRight } from "lucide-react";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { monthLabel } from "@/lib/monthLabel";
import { FilterBar, type ActiveFilter, type SortOption, type FieldDef } from "@/components/FilterBar";
import { InvestmentTransactionDrawer } from "@/components/InvestmentTransactionDrawer";
import { useDrawerKeyboard } from "@/hooks/useDrawerKeyboard";
import { buildGroupedRows, toggledSet, type GroupedRow } from "@/lib/tableEngine";
import type { InvestmentTransaction } from "@/api/types";
import { useElementHeight } from "@/hooks/useElementHeight";
import { useHashParam } from "@/hooks/useHashParam";
import { Pagination } from "@/components/ui/pagination";
import { usePagination } from "@/hooks/usePagination";

// ── Investment field / sort / group configs ───────────────────────────────────

const INV_TYPE_OPTIONS = ["Purchase", "Sale", "Dividend", "Foreign Dividend", "Interest", "Fees"].map((t) => ({ value: t, label: t }));

function investmentFields(accounts: string[]): FieldDef[] {
  return [
    { key: "trade_date",                label: "Date",     defaultOperator: "month",        defaultValue: "", editor: { type: "date" } },
    { key: "transaction_type_category", label: "Type",     defaultOperator: "equals",       defaultValue: "Purchase", editor: { type: "select", options: INV_TYPE_OPTIONS } },
    { key: "account_name",              label: "Account",  defaultOperator: "equals",       defaultValue: "", editor: { type: "select", options: accounts.map((a) => ({ value: a, label: a })) } },
    { key: "security_ticker",           label: "Security", defaultOperator: "contains",     defaultValue: "", editor: { type: "text", placeholder: "Ticker…" } },
    { key: "amount",                    label: "Amount",   defaultOperator: "greater_than", defaultValue: "", editor: { type: "amount" } },
  ];
}

const INV_SORT_FIELDS = [
  { key: "trade_date",                label: "Date"     },
  { key: "amount",                    label: "Amount"   },
  { key: "transaction_type",          label: "Type"     },
  { key: "account_name",              label: "Account"  },
  { key: "security_ticker",           label: "Security" },
];

const INV_GROUP_OPTIONS = [
  { key: "none",    label: "None"    },
  { key: "month",   label: "Month"   },
  { key: "type",    label: "Type"    },
  { key: "account", label: "Account" },
];

// ── Amount helper ─────────────────────────────────────────────────────────────

function txAmount(t: InvestmentTransaction): number {
  return t.amount_usd || t.cost_usd || t.income_usd || 0;
}

// ── Client-side filter logic ──────────────────────────────────────────────────

function applyInvestmentFilters(txns: InvestmentTransaction[], filters: ActiveFilter[], matchAll: boolean): InvestmentTransaction[] {
  if (!filters.length) return txns;
  return txns.filter((t) => {
    const results = filters.map((f) => {
      switch (f.field) {
        case "trade_date":
          if (f.operator === "month") return t.trade_date.startsWith(f.value);
          if (f.operator === "gte")   return t.trade_date >= f.value;
          if (f.operator === "lte")   return t.trade_date <= f.value;
          return true;
        case "transaction_type_category":
          return t.transaction_type_category === f.value;
        case "account_name":
          if (f.operator === "equals")   return t.account_name === f.value;
          if (f.operator === "contains") return t.account_name.toLowerCase().includes(f.value.toLowerCase());
          return true;
        case "security_ticker":
          if (f.operator === "contains") return (t.security_ticker ?? "").toUpperCase().includes(f.value.toUpperCase());
          if (f.operator === "equals")   return t.security_ticker === f.value;
          return true;
        case "amount": {
          const a = Math.abs(txAmount(t)), n = parseFloat(f.value);
          if (f.operator === "greater_than") return a > n;
          if (f.operator === "less_than")    return a < n;
          if (f.operator === "equals")       return a === n;
          return false;
        }
        default: return true;
      }
    });
    return matchAll ? results.every(Boolean) : results.some(Boolean);
  });
}

// ── Props ─────────────────────────────────────────────────────────────────────

interface Props {
  transactions: InvestmentTransaction[];
  isLoading?: boolean;
  stickyOffset?: number;
  pageSize?: number;
  showSecurity?: boolean;
  onReprocessed?: () => void;
  invalidateKey?: unknown[];
}

// ── Component ─────────────────────────────────────────────────────────────────

export function InvestmentTransactionTable({ transactions, isLoading, stickyOffset = 0, pageSize = 250, showSecurity = true, onReprocessed }: Props) {
  const [filters, setFilters] = useState<ActiveFilter[]>([]);
  const [matchAll, setMatchAll] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [groupBy, setGroupBy] = useState("month");
  const [primarySort, setPrimarySort] = useState<SortOption>({ field: "trade_date", dir: "desc" });
  const [secondarySort, setSecondarySort] = useState<SortOption | null>(null);
  const [page, setPage] = useState(0);

  const filterBarRef = useRef<HTMLDivElement>(null);
  const filterBarHeight = useElementHeight(filterBarRef, 37);
  const rowRefs = useRef<Map<string, HTMLTableRowElement>>(new Map());

  // Referentially stable handlers so the memoized rows don't re-render on
  // every parent state change.
  const [selectedId, setSelectedId] = useHashParam("itxid", { replace: true });
  // Derived from the current rows, so a refetch (e.g. after a reprocess)
  // shows up in the open drawer instead of a stale snapshot.
  const selected = useMemo(
    () => (selectedId ? transactions.find((t) => t.id === selectedId) ?? null : null),
    [transactions, selectedId],
  );
  const setSelected = (tx: InvestmentTransaction | null) => setSelectedId(tx ? tx.id : null);

  // Latest-ref pattern (as in TransactionTable): the hash setter is recreated
  // every render, so read it through a ref to keep the row handler stable.
  const selectedIdRef = useRef<string | null>(null);
  const setSelectedIdRef = useRef(setSelectedId);
  useEffect(() => {
    selectedIdRef.current = selected?.id ?? null;
    setSelectedIdRef.current = setSelectedId;
  });
  const handleRowClick = useCallback((tx: InvestmentTransaction) => {
    setSelectedIdRef.current(tx.id === selectedIdRef.current ? null : tx.id);
  }, []);
  const registerRowRef = useCallback((id: string, el: HTMLTableRowElement | null) => {
    if (el) rowRefs.current.set(id, el);
    else rowRefs.current.delete(id);
  }, []);


  useEffect(() => {
    if (selected) rowRefs.current.get(selected.id)?.scrollIntoView({ block: "nearest", behavior: "instant" });
  }, [selected?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Derive unique account names for field config
  const accounts = useMemo(() => {
    const names = new Set(transactions.map((t) => t.account_name));
    return Array.from(names).sort();
  }, [transactions]);

  const fields = useMemo(() => investmentFields(accounts), [accounts]);

  // Sort comparator — fields are INV_SORT_FIELDS keys
  function cmpBySort(s: SortOption, a: InvestmentTransaction, b: InvestmentTransaction): number {
    const mul = s.dir === "asc" ? 1 : -1;
    switch (s.field) {
      case "trade_date":       return mul * a.trade_date.localeCompare(b.trade_date);
      case "amount":           return mul * (txAmount(a) - txAmount(b));
      case "account_name":     return mul * (a.account_name ?? "").localeCompare(b.account_name ?? "");
      case "transaction_type": return mul * (a.transaction_type_category ?? "").localeCompare(b.transaction_type_category ?? "");
      case "security_ticker":  return mul * (a.security_ticker ?? "").localeCompare(b.security_ticker ?? "");
      default: return 0;
    }
  }

  function txGroupKey(tx: InvestmentTransaction): string {
    if (groupBy === "month")   return tx.trade_date.slice(0, 7);
    if (groupBy === "type")    return tx.transaction_type_category ?? "Unknown";
    if (groupBy === "account") return tx.account_name;
    return "";
  }

  function groupLabel(key: string): string {
    return groupBy === "month" ? monthLabel(key) : key;
  }

  const filtered = useMemo(() => {
    const postFilter = applyInvestmentFilters(transactions, filters, matchAll);
    const q = searchQuery.trim().toLowerCase();
    if (!q) return postFilter;
    const terms = q.split(/\s+/);
    return postFilter.filter((t) => {
      const haystack = [t.security_ticker, t.security_name, t.account_name, t.transaction_type_category, txAmount(t).toFixed(2)]
        .filter(Boolean).join(" ").toLowerCase();
      return terms.every((term) => haystack.includes(term));
    });
  }, [transactions, filters, matchAll, searchQuery]);

  const sorted = useMemo(() => {
    return [...filtered].sort((a, b) => {
      if (groupBy !== "none") {
        const gA = txGroupKey(a), gB = txGroupKey(b);
        if (gA !== gB) {
          const mul = (groupBy === "month" && primarySort.field === "trade_date")
            ? (primarySort.dir === "asc" ? 1 : -1)
            : 1;
          return gA < gB ? -mul : mul;
        }
      }
      const c1 = cmpBySort(primarySort, a, b);
      if (c1 !== 0) return c1;
      return secondarySort ? cmpBySort(secondarySort, a, b) : 0;
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtered, primarySort, secondarySort, groupBy]);

  const { page: currentPage, pageItems: paginated } = usePagination(sorted, page, pageSize);

  // Collapsed groups are reset in the onGroupByChange handler below instead of
  // reactively in an effect.
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set());

  function toggleGroup(label: string) {
    setCollapsedGroups((prev) => toggledSet(prev, label));
  }

  const rows: GroupedRow<InvestmentTransaction>[] = useMemo(
    () => buildGroupedRows({
      items: paginated,
      groupKey: groupBy === "none" ? null : txGroupKey,
      groupLabel,
      collapsed: collapsedGroups,
    }),
  // eslint-disable-next-line react-hooks/exhaustive-deps
  [paginated, groupBy, collapsedGroups]);

  const selectedIdx = selected ? paginated.findIndex((t) => t.id === selected.id) : -1;
  const prevTx = selectedIdx > 0 ? paginated[selectedIdx - 1] : null;
  const nextTx = selectedIdx < paginated.length - 1 ? paginated[selectedIdx + 1] : null;

  useDrawerKeyboard({
    onClose: () => setSelected(null),
    onPrev: prevTx ? () => setSelected(prevTx) : undefined,
    onNext: nextTx ? () => setSelected(nextTx) : undefined,
    onFirst: paginated[0] ? () => setSelected(paginated[0]) : undefined,
    onLast: paginated.at(-1) ? () => setSelected(paginated.at(-1)!) : undefined,
  });

  return (
    <div className="flex overflow-hidden bg-card">
      <div className="min-w-0 flex-1">
        {/* Sticky filter bar */}
        <div ref={filterBarRef} className="sticky z-20 border-b bg-card px-3 py-1.5" style={{ top: stickyOffset }}>
          <FilterBar
            filters={filters}
            matchAll={matchAll}
            onChange={(f) => { setFilters(f); setPage(0); }}
            onMatchAllChange={(v) => { setMatchAll(v); setPage(0); }}
            searchQuery={searchQuery}
            onSearchChange={(q) => { setSearchQuery(q); setPage(0); }}
            resultCount={isLoading ? undefined : filtered.length}
            isLoading={isLoading}
            fields={fields}
            display={{
              sortFields: INV_SORT_FIELDS,
              groupOptions: INV_GROUP_OPTIONS,
              groupBy,
              onGroupByChange: (g) => { if (g !== groupBy) setCollapsedGroups(new Set()); setGroupBy(g); setPage(0); },
              primarySort,
              onPrimarySort: (s) => { setPrimarySort(s); setPage(0); },
              secondarySort,
              onSecondarySort: (s) => { setSecondarySort(s); setPage(0); },
            }}
          />
        </div>

        <table className="w-full text-sm">
          <thead
            className="bg-card z-10"
            style={{ position: "sticky", top: stickyOffset + filterBarHeight - 1 }}
          >
            <tr className="border-b text-xs text-muted-foreground">
              <th className="px-4 py-2.5 text-left font-medium w-28">Date</th>
              {showSecurity && <th className="px-4 py-2.5 text-left font-medium">Security</th>}
              <th className="px-4 py-2.5 text-left font-medium">Account</th>
              <th className="px-4 py-2.5 text-left font-medium">Type</th>
              <th className="px-4 py-2.5 text-right font-medium w-20">Qty</th>
              <th className="px-4 py-2.5 text-right font-medium w-28">Amount</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {isLoading && Array.from({ length: 8 }).map((_, i) => (
              <tr key={i}>
                {["w-20", "w-full max-w-48", "w-32", "w-20", "w-12", "w-16"].map((w, j) => (
                  <td key={j} className="px-4 py-3">
                    <div className={cn("h-3.5 animate-pulse rounded bg-muted", j >= 4 ? "ml-auto " + w : w)} />
                  </td>
                ))}
              </tr>
            ))}
            {!isLoading && sorted.length === 0 && (
              <tr>
                <td colSpan={showSecurity ? 6 : 5} className="px-4 py-10 text-center text-muted-foreground">
                  No investment transactions
                </td>
              </tr>
            )}
            {!isLoading && rows.map((row, ri) => {
              if (row.type === "header") {
                const collapsed = collapsedGroups.has(row.label);
                return (
                  <tr
                    key={`hdr-${ri}`}
                    onClick={() => toggleGroup(row.label)}
                    className="cursor-pointer bg-muted/30 hover:bg-muted/50 transition-colors"
                  >
                    <td colSpan={showSecurity ? 6 : 5} className="px-4 py-1.5">
                      <div className="flex items-center gap-1.5 text-xs font-semibold text-muted-foreground">
                        <ChevronRight size={12} className={cn("transition-transform", !collapsed && "rotate-90")} />
                        {row.label}
                        <span className="ml-1 font-normal opacity-60">{row.count}</span>
                      </div>
                    </td>
                  </tr>
                );
              }
              const tx = row.tx;
              return (
                <InvestmentRow
                  key={tx.id}
                  tx={tx}
                  showSecurity={showSecurity}
                  isSelected={tx.id === selected?.id}
                  onRowClick={handleRowClick}
                  registerRef={registerRowRef}
                />
              );
            })}
          </tbody>
        </table>

        {/* Pagination */}
        {!isLoading && (
          <Pagination variant="range" page={currentPage} pageSize={pageSize} total={sorted.length} onPageChange={setPage} />
        )}
      </div>

      <div
        className={cn(
          "shrink-0 transition-[width] duration-200 overflow-hidden",
          selected ? "w-80" : "w-0"
        )}
      >
        {selected && (
          <InvestmentTransactionDrawer
            inline
            tx={selected}
            onClose={() => setSelected(null)}
            onReprocessed={onReprocessed}
            onPrev={prevTx ? () => setSelected(prevTx) : undefined}
            onNext={nextTx ? () => setSelected(nextTx) : undefined}
            onFirst={paginated[0] ? () => setSelected(paginated[0]) : undefined}
            onLast={paginated.at(-1) ? () => setSelected(paginated.at(-1)!) : undefined}
          />
        )}
      </div>
    </div>
  );
}

// Memoized row — mirrors TransactionTable's TransactionRow: re-rendering
// every <tr> on each drawer toggle / filter keystroke dominated interaction
// cost. Handlers passed in are referentially stable.
const InvestmentRow = memo(function InvestmentRow({
  tx,
  showSecurity,
  isSelected,
  onRowClick,
  registerRef,
}: {
  tx: InvestmentTransaction;
  showSecurity: boolean;
  isSelected: boolean;
  onRowClick: (tx: InvestmentTransaction) => void;
  registerRef: (id: string, el: HTMLTableRowElement | null) => void;
}) {
  return (
    <tr
      ref={(el) => registerRef(tx.id, el)}
      onClick={() => onRowClick(tx)}
      className={cn("cursor-pointer transition-colors hover:bg-muted/40", isSelected && "bg-primary/5")}
    >
      <td className="px-4 py-2.5 text-muted-foreground whitespace-nowrap">{formatDate(tx.trade_date)}</td>
      {showSecurity && (
        <td className="px-4 py-2.5 max-w-0 w-full">
          <p className="font-medium truncate">{tx.security_ticker ?? "—"}</p>
          {tx.security_name && (
            <p className="text-xs text-muted-foreground truncate max-w-48">{tx.security_name}</p>
          )}
        </td>
      )}
      <td className="px-4 py-2.5 text-muted-foreground text-xs whitespace-nowrap">{tx.account_name}</td>
      <td className="px-4 py-2.5 text-xs text-muted-foreground whitespace-nowrap">{tx.transaction_type_category}</td>
      <td className="px-4 py-2.5 text-right tabular-nums text-muted-foreground text-xs">
        {tx.quantity > 0 ? tx.quantity.toLocaleString() : "—"}
      </td>
      <td className="px-4 py-2.5 text-right tabular-nums font-mono">
        {formatCurrency(txAmount(tx))}
      </td>
    </tr>
  );
});
