import { useState, useMemo, useEffect, useRef, useCallback, useDeferredValue, memo } from "react";
import { useLocation } from "react-router-dom";
import { useQuery, useMutation, useQueryClient, useIsFetching } from "@tanstack/react-query";
import { ArrowUp, ArrowDown, ArrowUpDown, ArrowLeftRight, ChevronRight, Clock, CreditCard, Download, RefreshCw, Square, SquareCheck } from "lucide-react";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/toast";
import { amountColor, paymentSettlementStatus } from "@/lib/transactions";
import { monthLabel } from "@/lib/monthLabel";
import { useHashParam } from "@/hooks/useHashParam";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { FilterBar, type ActiveFilter, type GroupByKey, type ColumnKey, type SortOption } from "@/components/FilterBar";
import { useTransactionDefaults } from "@/hooks/useTransactionDefaults";
import { buildTransactionsCsv, downloadCsv } from "@/lib/csv";
import { ExportToOfficeButton } from "@/components/ExportToOfficeButton";
import { TransactionDrawer } from "@/components/TransactionDrawer";
import { BulkActionBar } from "@/components/BulkActionBar";
import { rowGroupKey } from "@/lib/transactionTable";
import { useTransactionRows } from "@/hooks/useTransactionRows";
import { buildGroupedRows, toggledSet, type GroupedRow } from "@/lib/tableEngine";
import type { CashTransaction } from "@/api/types";
import { invalidate, keys } from "@/api/keys";
import { useElementHeight } from "@/hooks/useElementHeight";
import { Pagination } from "@/components/ui/pagination";
import { SavedItemsMenu } from "@/components/SavedItemsMenu";

export type TransactionColumn = "date" | "description" | "merchant" | "category" | "account" | "amount" | "tags" | "note";

interface Props {
  transactions: CashTransaction[];
  isLoading?: boolean;
  columns?: TransactionColumn[];
  resetKey?: unknown;
  stickyOffset?: number;
  initialFilters?: ActiveFilter[];
  /** Server-side scope for the Office export — the filter this table's page
   *  already applied before handing over `transactions` (an account, a
   *  category, a tag). The table's own filters, search and transfer toggle
   *  are added to it; without it an export would reach past the page. */
  exportScope?: Record<string, string | number | undefined>;
}

type SortKey = "date" | "amount"; // kept for SortableHeader compat
type SortDir = "asc" | "desc";

// ── Module-level grouping helpers ─────────────────────────────────────────────

function rowGroupLabel(key: string, groupBy: GroupByKey): string {
  return groupBy === "month" ? monthLabel(key) : key;
}

export function TransactionTable({ transactions, isLoading, columns: columnsProp, resetKey, stickyOffset = 0, initialFilters, exportScope }: Props) {
  const defaults = useTransactionDefaults();
  const qc = useQueryClient();
  const [primarySort, setPrimarySort] = useState<SortOption>(defaults.primarySort);
  const [secondarySort, setSecondarySort] = useState<SortOption | null>(defaults.secondarySort);
  const [columns, setColumns] = useState<ColumnKey[]>((columnsProp as ColumnKey[] | undefined) ?? defaults.columns);
  const [groupBy, setGroupBy] = useState<GroupByKey>(defaults.groupBy);
  const pageSize = defaults.pageSize;
  const combineMerchantDesc = defaults.combineMerchantDesc;
  const codeStyleFallback = defaults.codeStyleFallback;
  const showTransfers = defaults.showTransfers;
  const showCheckboxes = defaults.showCheckboxes;
  const [page, setPage] = useState(0);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const lastCheckedIndexRef = useRef<number>(-1);
  const filterBarRef = useRef<HTMLDivElement>(null);
  const bulkBarRef = useRef<HTMLDivElement>(null);
  const filterBarHeight = useElementHeight(filterBarRef, 37);
  const bulkBarHeight = useElementHeight(bulkBarRef);
  const location = useLocation();
  const filterKey = `txn_filters:${location.pathname}`;
  // Explicit initial filters (e.g. chart drill-down URL params) win; otherwise
  // restore the filters persisted for this path from sessionStorage.
  const [filters, setFilters] = useState<ActiveFilter[]>(() => {
    if (initialFilters?.length) return initialFilters;
    try { return JSON.parse(sessionStorage.getItem(filterKey) ?? "[]"); } catch { return []; }
  });
  const [matchAll, setMatchAll] = useState(true);
  const [activeViewId, setActiveViewId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");

  // Persist filters to sessionStorage whenever they change
  useEffect(() => {
    sessionStorage.setItem(filterKey, JSON.stringify(filters));
  }, [filters, filterKey]);

  const { data: savedViews = [] } = useQuery(queries.savedViews());

  const createView = useMutation({
    mutationFn: (name: string) =>
      api.post<import("@/api/types").SavedView>("/saved_views", {
        name,
        conditions: filters,
        match_all: matchAll,
        group_by: groupBy,
        primary_sort: primarySort,
        secondary_sort: secondarySort,
      }),
    onSuccess: (view) => {
      invalidate(qc, keys.savedViews);
      setActiveViewId(view.id);
    },
  });

  const deleteView = useMutation({
    mutationFn: (id: string) => api.delete(`/saved_views/${id}`),
    onSuccess: (_: unknown, id: string) => {
      invalidate(qc, keys.savedViews);
      if (activeViewId === id) setActiveViewId(null);
    },
  });

  function applyView(view: import("@/api/types").SavedView) {
    setActiveViewId(view.id);
    setMatchAll(view.match_all);
    setFilters(view.conditions.map((c, i) => ({ _key: i + 1, field: c.field, operator: c.operator, value: String(c.value ?? "") })));
    clearSelection();
    if (view.group_by != null) {
      if (view.group_by !== groupBy) setCollapsedGroups(new Set());
      setGroupBy(view.group_by as GroupByKey);
    }
    if (view.primary_sort != null) setPrimarySort(view.primary_sort as SortOption);
    if (view.secondary_sort !== undefined) setSecondarySort((view.secondary_sort ?? null) as SortOption | null);
    setPage(0);
  }
  const [rawTxId, setTxId] = useHashParam("txid", { replace: true });
  const rowRefs = useRef<Map<string, HTMLTableRowElement>>(new Map());

  const selected = useMemo(
    () => (rawTxId ? transactions.find((t) => t.id === rawTxId) ?? null : null),
    [transactions, rawTxId],
  );

  // Latest-ref pattern: keeps the row click handler referentially stable so
  // memoized rows don't all re-render when the selection (or the hash-param
  // setter, which is recreated per render) changes.
  const selectedIdRef = useRef<string | null>(null);
  const setTxIdRef = useRef(setTxId);
  useEffect(() => {
    selectedIdRef.current = selected?.id ?? null;
    setTxIdRef.current = setTxId;
  });
  const handleRowClick = useCallback((id: string) => {
    setTxIdRef.current(id === selectedIdRef.current ? null : id);
  }, []);

  const registerRowRef = useCallback((id: string, el: HTMLTableRowElement | null) => {
    if (el) rowRefs.current.set(id, el);
    else rowRefs.current.delete(id);
  }, []);

  useEffect(() => {
    if (selected) rowRefs.current.get(selected.id)?.scrollIntoView({ block: "nearest", behavior: "instant" });
  }, [selected?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const prevResetKey = useRef(resetKey);
  useEffect(() => {
    if (prevResetKey.current === resetKey) return;
    prevResetKey.current = resetKey;
    setPage(0);
    setTxId(null);
    setFilters(initialFilters ?? []);
    setSelectedIds(new Set());
    lastCheckedIndexRef.current = -1;
  }, [resetKey]); // eslint-disable-line react-hooks/exhaustive-deps

  // Row selection is cleared wherever filters/matchAll change (FilterBar
  // handlers, applyView) instead of reactively in an effect.
  function clearSelection() {
    setSelectedIds(new Set());
    lastCheckedIndexRef.current = -1;
  }

  function toggleSort(key: SortKey) {
    setPrimarySort((p) => p.field === key ? { ...p, dir: p.dir === "asc" ? "desc" : "asc" } : { field: key, dir: "desc" });
    setPage(0);
  }

  // Search is deferred so keystrokes stay responsive: the input re-renders
  // immediately while the filtered rows catch up in a non-blocking pass.
  const deferredSearchQuery = useDeferredValue(searchQuery);

  const { searched, paginated, page: currentPage } = useTransactionRows(transactions, {
    filters, matchAll, showTransfers, primarySort, secondarySort, groupBy,
    searchQuery: deferredSearchQuery, page, pageSize,
  });

  const pageIds = useMemo(() => paginated.map((tx) => tx.id), [paginated]);
  const allPageSelected = pageIds.length > 0 && pageIds.every((id) => selectedIds.has(id));
  const somePageSelected = pageIds.some((id) => selectedIds.has(id));

  const toggleSelect = useCallback((id: string, paginatedIndex: number, shiftKey: boolean) => {
    if (shiftKey && lastCheckedIndexRef.current !== -1) {
      const from = Math.min(lastCheckedIndexRef.current, paginatedIndex);
      const to = Math.max(lastCheckedIndexRef.current, paginatedIndex);
      setSelectedIds((prev) => {
        const next = new Set(prev);
        for (let i = from; i <= to; i++) next.add(paginated[i].id);
        return next;
      });
    } else {
      setSelectedIds((prev) => {
        const next = new Set(prev);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        return next;
      });
      lastCheckedIndexRef.current = paginatedIndex;
    }
  }, [paginated]);
  function toggleAllPage() {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (allPageSelected) pageIds.forEach((id) => next.delete(id));
      else pageIds.forEach((id) => next.add(id));
      return next;
    });
  }

  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set());

  function toggleGroup(label: string) {
    setCollapsedGroups((prev) => toggledSet(prev, label));
  }

  const rows: GroupedRow<CashTransaction>[] = useMemo(
    () => buildGroupedRows({
      items: paginated,
      groupKey: groupBy === "none" ? null : (tx) => rowGroupKey(tx, groupBy),
      groupLabel: (key) => rowGroupLabel(key, groupBy),
      collapsed: collapsedGroups,
    }),
    [paginated, groupBy, collapsedGroups],
  );

  const idx = selected ? paginated.findIndex((t) => t.id === selected.id) : -1;
  const prevTx = idx > 0 ? paginated[idx - 1] : null;
  const nextTx = idx < paginated.length - 1 ? paginated[idx + 1] : null;

  return (
    <div className="flex min-h-screen">
      {/* Table column */}
      <div className="min-w-0 flex-1">
      {/* Inline filter bar — sticky so it stays visible while scrolling */}
      <div ref={filterBarRef} className="sticky z-20 border-b bg-card px-3 py-1.5 flex items-center gap-2" style={{ top: stickyOffset }}>
        <div className="flex-1 min-w-0">
          <FilterBar
            filters={filters}
            matchAll={matchAll}
            onChange={(f) => { setFilters(f); setPage(0); setActiveViewId(null); clearSelection(); }}
            onMatchAllChange={(v) => { if (v !== matchAll) clearSelection(); setMatchAll(v); setActiveViewId(null); }}
            resultCount={isLoading ? undefined : searched.length}
            isLoading={isLoading}
            searchQuery={searchQuery}
            onSearchChange={(q) => { setSearchQuery(q); setPage(0); }}
            display={{
              columns,
              onColumnsChange: setColumns,
              groupBy,
              onGroupByChange: (g) => { if (g !== groupBy) setCollapsedGroups(new Set()); setGroupBy(g); },
              primarySort,
              onPrimarySort: (s) => { setPrimarySort(s); setPage(0); },
              secondarySort,
              onSecondarySort: (s) => { setSecondarySort(s); setPage(0); },
              showTransfers,
              onShowTransfersChange: defaults.setShowTransfers,
            }}
          />
        </div>
        {/* Hiding the checkbox column drops any in-progress selection so the
            bulk bar can't act on rows the user can no longer see. */}
        <Button
          variant="ghost"
          size="icon-sm"
          className={cn("shrink-0", showCheckboxes ? "text-foreground" : "text-muted-foreground hover:text-foreground")}
          title={showCheckboxes ? "Hide selection checkboxes" : "Show selection checkboxes"}
          aria-label={showCheckboxes ? "Hide selection checkboxes" : "Show selection checkboxes"}
          aria-pressed={showCheckboxes}
          onClick={() => { defaults.setShowCheckboxes(!showCheckboxes); clearSelection(); }}
        >
          {showCheckboxes ? <SquareCheck size={13} /> : <Square size={13} />}
        </Button>

        <RefreshButton />

        {/* Export what the table currently shows (all pages, current sort) —
            selected rows only when a selection is active. */}
        <Button
          variant="ghost"
          size="icon-sm"
          className="shrink-0 text-muted-foreground hover:text-foreground"
          title="Export CSV"
          aria-label="Export CSV"
          disabled={searched.length === 0}
          onClick={() => {
            const rows = selectedIds.size > 0 ? searched.filter((t) => selectedIds.has(t.id)) : searched;
            downloadCsv(`transactions-${new Date().toISOString().slice(0, 10)}.csv`, buildTransactionsCsv(rows));
          }}
        >
          <Download size={13} />
        </Button>

        {/* The same table, as a spreadsheet in Office. The server rebuilds it
            from these filters rather than taking the loaded rows, so the sheet
            covers the whole filtered set and can be refreshed later. */}
        <ExportToOfficeButton
          dataset="transactions"
          filters={{
            ...exportScope,
            conditions: filters.length > 0 ? filters.map(({ field, operator, value }) => ({ field, operator, value })) : undefined,
            match_all: filters.length > 0 ? matchAll : undefined,
            search: searchQuery.trim() || undefined,
            show_transfers: showTransfers ? undefined : false,
          }}
        />

        {/* Saved views */}
        <SavedItemsMenu
          noun="view"
          saveLabel="Save current as view"
          items={savedViews}
          activeId={activeViewId}
          saving={createView.isPending}
          onSave={(name) => createView.mutateAsync(name)}
          onApply={applyView}
          onDelete={(view) => deleteView.mutate(view.id)}
          className="shrink-0"
        />
      </div>

      <div
        ref={bulkBarRef}
        className="sticky z-20 overflow-hidden bg-card"
        style={{
          top: stickyOffset + filterBarHeight,
          maxHeight: selectedIds.size > 0 ? "60px" : "0px",
          opacity: selectedIds.size > 0 ? 1 : 0,
          transition: "max-height 150ms ease-out, opacity 120ms ease-out",
        }}
      >
        <BulkActionBar
          selectedIds={selectedIds}
          onClear={() => setSelectedIds(new Set())}
        />
      </div>

      <table className="w-full text-sm">
        <thead className="z-10">
          {(() => {
            const thStyle: React.CSSProperties = {
              position: "sticky",
              top: stickyOffset + filterBarHeight + bulkBarHeight - 1,
              backgroundColor: "var(--color-card)",
              zIndex: 10,
            };
            return (
              <tr className="border-b text-xs text-muted-foreground">
                {showCheckboxes && (
                  <th className="w-8 pl-3 pr-0 py-2.5" style={thStyle}>
                    {/* Inline callback ref runs each render, keeping the native
                        indeterminate flag in sync without a forwarded ref. */}
                    <span
                      ref={(node) => {
                        const el = node?.querySelector("input");
                        if (el) el.indeterminate = somePageSelected && !allPageSelected;
                      }}
                    >
                      <Checkbox
                        checked={allPageSelected}
                        onChange={toggleAllPage}
                        aria-label="Select all rows on this page"
                      />
                    </span>
                  </th>
                )}
                {columns.includes("date") && (
                  <SortableHeader label="Date" sortKey="date" current={primarySort.field as SortKey} dir={primarySort.dir as "asc"|"desc"} onSort={toggleSort} className="w-28" thStyle={thStyle} />
                )}
                {(columns.includes("description") || (combineMerchantDesc && columns.includes("merchant"))) && (
                  <th className="px-4 py-2.5 text-left font-medium" style={thStyle}>{combineMerchantDesc ? "Merchant" : "Description"}</th>
                )}
                {!combineMerchantDesc && columns.includes("merchant") && (
                  <th className="px-4 py-2.5 text-left font-medium" style={thStyle}>Merchant</th>
                )}
                {columns.includes("category") && (
                  <th className="px-4 py-2.5 text-left font-medium" style={thStyle}>Category</th>
                )}
                {columns.includes("account") && (
                  <th className="px-4 py-2.5 text-left font-medium" style={thStyle}>Account</th>
                )}
                {columns.includes("type") && (
                  <th className="px-4 py-2.5 text-left font-medium" style={thStyle}>Type</th>
                )}
                {columns.includes("amount") && (
                  <SortableHeader label="Amount" sortKey="amount" current={primarySort.field as SortKey} dir={primarySort.dir as "asc"|"desc"} onSort={toggleSort} className="w-28 text-right" right thStyle={thStyle} />
                )}
              </tr>
            );
          })()}
        </thead>
        <tbody className="divide-y">
          {isLoading && Array.from({ length: 8 }).map((_, i) => (
            <tr key={i}>
              {showCheckboxes && <td className="w-8 pl-3 pr-0 py-3" />}
              {columns.map((col) => (
                <td key={col} className="px-4 py-3">
                  <Skeleton className={cn("h-3.5 rounded", col === "amount" ? "ml-auto w-16" : col === "date" ? "w-20" : "w-full max-w-48")} />
                </td>
              ))}
            </tr>
          ))}
          {!isLoading && searched.length === 0 && (
            <tr>
              <td colSpan={columns.length + (showCheckboxes ? 1 : 0)}>
                <EmptyState
                  title={filters.length > 0 || searchQuery.trim()
                    ? "No transactions match the current filters."
                    : "No transactions yet."}
                />
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
                  <td colSpan={columns.length + (showCheckboxes ? 1 : 0)} className="px-4 py-1.5">
                    <div className="flex items-center gap-1.5 text-xs font-semibold text-muted-foreground">
                      <ChevronRight size={12} className={cn("transition-transform", !collapsed && "rotate-90")} />
                      {row.label}
                      <span className="ml-1 font-normal opacity-60">{row.count}</span>
                    </div>
                  </td>
                </tr>
              );
            }
            return (
              <TransactionRow
                key={row.tx.id}
                tx={row.tx}
                paginatedIndex={row.pIdx}
                columns={columns}
                combineMerchantDesc={combineMerchantDesc}
                codeStyleFallback={codeStyleFallback}
                showTransfers={showTransfers}
                isSelected={row.tx.id === selected?.id}
                isChecked={selectedIds.has(row.tx.id)}
                showCheckbox={showCheckboxes}
                onToggleSelect={toggleSelect}
                onRowClick={handleRowClick}
                registerRef={registerRowRef}
              />
            );
          })}
        </tbody>
      </table>

      {/* Pagination */}
      {!isLoading && (
        <Pagination variant="range" page={currentPage} pageSize={pageSize} total={searched.length} onPageChange={setPage} />
      )}

      </div>{/* end table column */}

      {/* Sliding detail panel */}
      <div
        className={cn(
          "flex-shrink-0 border-l overflow-y-auto transition-[width] duration-200 sticky self-start",
          selected ? "w-80" : "w-0"
        )}
        style={{ top: stickyOffset, height: `calc(100vh - ${stickyOffset}px)` }}
      >
        {selected && (
          <TransactionDrawer
            tx={selected}
            headerHeight={filterBarHeight}
            onClose={() => setTxId(null)}
            onPrev={prevTx ? () => setTxId(String(prevTx.id)) : undefined}
            onNext={nextTx ? () => setTxId(String(nextTx.id)) : undefined}
            onFirst={paginated[0] ? () => setTxId(String(paginated[0].id)) : undefined}
            onLast={paginated.at(-1) ? () => setTxId(String(paginated.at(-1)!.id)) : undefined}
          />
        )}
      </div>
    </div>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Refresh control in its own component so useIsFetching subscription churn
 *  (every background page arrival) re-renders this button, not the table. */
function RefreshButton() {
  const qc = useQueryClient();
  const isFetchingTxns = useIsFetching({ queryKey: keys.cashTransactions }) > 0;
  const refreshPending = useRef(false);

  function refresh() {
    refreshPending.current = true;
    invalidate(qc, keys.cashTransactions);
  }

  useEffect(() => {
    if (!isFetchingTxns && refreshPending.current) {
      refreshPending.current = false;
      toast.success("Table refreshed");
    }
  }, [isFetchingTxns]);

  return (
    <Button
      variant="ghost"
      size="icon-sm"
      onClick={refresh}
      disabled={isFetchingTxns}
      className="shrink-0 text-muted-foreground hover:text-foreground"
      title="Refresh"
      aria-label="Refresh"
    >
      <RefreshCw size={13} className={isFetchingTxns ? "animate-spin" : ""} />
    </Button>
  );
}

// Memoized row: with ~250 rows per page, re-rendering every <tr> on each
// checkbox click / drawer toggle / background page arrival dominated
// interaction cost. Handlers passed in are referentially stable.
const TransactionRow = memo(function TransactionRow({
  tx,
  paginatedIndex,
  columns,
  combineMerchantDesc,
  codeStyleFallback,
  showTransfers,
  isSelected,
  isChecked,
  showCheckbox,
  onToggleSelect,
  onRowClick,
  registerRef,
}: {
  tx: CashTransaction;
  paginatedIndex: number;
  columns: ColumnKey[];
  combineMerchantDesc: boolean;
  codeStyleFallback: boolean;
  showTransfers: boolean;
  isSelected: boolean;
  isChecked: boolean;
  showCheckbox: boolean;
  onToggleSelect: (id: string, paginatedIndex: number, shiftKey: boolean) => void;
  onRowClick: (id: string) => void;
  registerRef: (id: string, el: HTMLTableRowElement | null) => void;
}) {
  const settlementStatus = paymentSettlementStatus(tx);
  return (
    <tr
      ref={(el) => registerRef(tx.id, el)}
      onClick={() => onRowClick(tx.id)}
      className={cn("cursor-pointer transition-colors hover:bg-muted/40", isSelected && "bg-primary/5")}
    >
      {showCheckbox && (
        <td className="w-8 pl-3 pr-0 py-3" onClick={(e) => e.stopPropagation()}>
          <Checkbox
            checked={isChecked}
            onChange={(e) => onToggleSelect(tx.id, paginatedIndex, (e.nativeEvent as MouseEvent).shiftKey)}
            aria-label={`Select transaction ${tx.description}`}
          />
        </td>
      )}
      {columns.includes("date") && (
        <td className="px-4 py-3 text-muted-foreground whitespace-nowrap">{formatDate(tx.transaction_date)}</td>
      )}
      {(columns.includes("description") || (combineMerchantDesc && columns.includes("merchant"))) && (
        <td className="px-4 py-3 max-w-0 w-full">
          {tx.loan_name
            ? <p className="truncate">{tx.loan_name}</p>
            : combineMerchantDesc && !tx.merchant_name && codeStyleFallback
              ? <code className="inline-block max-w-full truncate rounded bg-muted px-1.5 py-0.5 font-mono text-xs text-muted-foreground">{tx.description}</code>
              : <p className="truncate">{combineMerchantDesc ? (tx.merchant_name ?? tx.description) : tx.description}</p>
          }
          {((columns.includes("tags") && tx.tags.length > 0) || (columns.includes("note") && tx.memo) || (tx.transfer_id && (showTransfers || (tx.transfer_include_in_spend && tx.amount < 0))) || settlementStatus) && (
            <div className="mt-0.5 flex items-center gap-1.5 overflow-hidden">
              {tx.transfer_id && (showTransfers || (tx.transfer_include_in_spend && tx.amount < 0)) && (
                <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-muted px-1.5 py-px text-tiny font-medium text-muted-foreground">
                  {tx.transfer_kind === "credit_card_payment" ? <CreditCard size={9} /> : <ArrowLeftRight size={9} />}
                  {tx.transfer_kind === "credit_card_payment"
                    ? "Card payment"
                    : tx.transfer_kind === "loan_payment"
                      ? "Loan payment"
                      : "Transfer"}
                </span>
              )}
              {settlementStatus && (
                <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-muted px-1.5 py-px text-tiny font-medium text-muted-foreground">
                  <Clock size={9} />
                  {settlementStatus === "awaiting" ? "Pending settlement" : "Unmatched payment"}
                </span>
              )}
              {columns.includes("tags") && tx.tags.map((tag) => (
                <span key={tag.id} className="shrink-0 rounded-full bg-primary/10 px-1.5 py-px text-tiny font-medium text-primary">
                  {tag.name}
                </span>
              ))}
              {columns.includes("note") && tx.memo && (
                <span className="truncate text-xs text-muted-foreground">{tx.memo}</span>
              )}
            </div>
          )}
        </td>
      )}
      {!combineMerchantDesc && columns.includes("merchant") && (
        <td className="px-4 py-3 text-muted-foreground whitespace-nowrap">{tx.merchant_name ?? <span className="opacity-30">—</span>}</td>
      )}
      {columns.includes("category") && (
        <td className="px-4 py-3 text-muted-foreground whitespace-nowrap">{tx.category_name ?? <span className="opacity-30">—</span>}</td>
      )}
      {columns.includes("account") && (
        <td className="px-4 py-3 text-muted-foreground whitespace-nowrap">{tx.account_name ?? <span className="opacity-30">—</span>}</td>
      )}
      {columns.includes("type") && (
        <td className="px-4 py-3 text-muted-foreground whitespace-nowrap capitalize">{tx.transaction_type ?? <span className="opacity-30">—</span>}</td>
      )}
      {columns.includes("amount") && (
        <td className={cn("px-4 py-3 text-right tabular-nums font-mono", amountColor(tx))}>{formatCurrency(tx.amount)}</td>
      )}
    </tr>
  );
});

function SortableHeader({ label, sortKey, current, dir, onSort, className, right, thStyle }: {
  label: string;
  sortKey: SortKey;
  current: SortKey;
  dir: SortDir;
  onSort: (k: SortKey) => void;
  className?: string;
  right?: boolean;
  thStyle?: React.CSSProperties;
}) {
  const active = current === sortKey;
  const Icon = active ? (dir === "asc" ? ArrowUp : ArrowDown) : ArrowUpDown;
  return (
    <th className={cn("px-4 py-2.5 font-medium", className)} style={thStyle}>
      <button
        onClick={() => onSort(sortKey)}
        className={cn("flex items-center gap-1 rounded hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary", right && "ml-auto")}
      >
        {right && <Icon size={11} className={active ? "opacity-100" : "opacity-30"} />}
        {label}
        {!right && <Icon size={11} className={active ? "opacity-100" : "opacity-30"} />}
      </button>
    </th>
  );
}
