import { useState, useEffect, useRef } from "react";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { useHashParam } from "@/hooks/useHashParam";
import { useTransactionDefaults } from "@/hooks/useTransactionDefaults";
import { useTransactionRows } from "@/hooks/useTransactionRows";
import { TransactionDrawer } from "./TransactionDrawer";
import { TransactionTable, type TransactionColumn } from "./TransactionTable";
import { amountColor } from "@/lib/transactions";
import type { CashTransaction } from "@/api/types";
import type { ActiveFilter, SortOption } from "@/components/FilterBar";
import { Pagination } from "@/components/ui/pagination";

interface Props {
  transactions: CashTransaction[];
  isLoading?: boolean;
  columns?: TransactionColumn[];
  resetKey?: unknown;
  stickyOffset?: number;
  initialFilters?: ActiveFilter[];
  /** Forwarded to the desktop table's Office export; the mobile list has no
   *  export control of its own. */
  exportScope?: Record<string, string | number | undefined>;
}

const PAGE_SIZE = 100;
// The mobile list has no sort or filter controls: newest first, filtered only
// by what the page handed over (e.g. chart drill-down params).
const SORT: SortOption = { field: "date", dir: "desc" };
const NO_FILTERS: ActiveFilter[] = [];

export function TransactionList({ transactions, isLoading, columns, resetKey, initialFilters }: Props) {
  const { showTransfers } = useTransactionDefaults();
  const [page, setPage] = useState(0);
  const [rawTxId, setTxId] = useHashParam("txid", { replace: true });

  const selected = rawTxId ? (transactions.find((t) => t.id === rawTxId) ?? null) : null;

  const prevResetKey = useRef(resetKey);
  useEffect(() => {
    if (prevResetKey.current === resetKey) return;
    prevResetKey.current = resetKey;
    setPage(0);
    setTxId(null);
  }, [resetKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const { sorted, paginated, page: currentPage } = useTransactionRows(transactions, {
    filters: initialFilters ?? NO_FILTERS,
    matchAll: true,
    showTransfers,
    primarySort: SORT,
    secondarySort: null,
    groupBy: "none",
    searchQuery: "",
    page,
    pageSize: PAGE_SIZE,
  });

  // Determine what secondary info to show based on active columns
  const showMerchant = !columns || columns.includes("merchant");
  const showCategory = !columns || columns.includes("category");
  const showAccount = !columns || columns.includes("account");

  function secondaryLabel(tx: CashTransaction): string {
    if (showMerchant && tx.merchant_name) return tx.merchant_name;
    if (showCategory && tx.category_name) return tx.category_name;
    if (showAccount && tx.account_name) return tx.account_name;
    return tx.description ?? "—";
  }

  function tertiaryLabel(tx: CashTransaction): string {
    const parts: string[] = [];
    if (showCategory && tx.category_name && showMerchant && tx.merchant_name) parts.push(tx.category_name);
    else if (showCategory && tx.category_name && !showMerchant) parts.push(tx.category_name);
    if (showAccount && tx.account_name) parts.push(tx.account_name);
    return parts.join(" · ");
  }

  return (
    <div className="relative">
      {isLoading && (
        <div className="divide-y">
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="flex items-center justify-between px-4 py-3 gap-3">
              <div className="flex-1 space-y-1.5 min-w-0">
                <Skeleton className="h-3.5 rounded w-3/4" />
                <Skeleton className="h-3 rounded w-1/2" />
              </div>
              <Skeleton className="h-3.5 rounded w-16 shrink-0" />
            </div>
          ))}
        </div>
      )}

      {!isLoading && sorted.length === 0 && (
        <EmptyState title="No transactions yet." />
      )}

      {!isLoading && (
        <div className="divide-y">
          {paginated.map((tx) => (
            <button
              key={tx.id}
              onClick={() => setTxId(tx.id === selected?.id ? null : tx.id)}
              className={cn(
                "w-full flex items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-muted/40 active:bg-muted/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
                tx.id === selected?.id && "bg-primary/5",
              )}
            >
              <div className="flex-1 min-w-0">
                {/* Top row: description */}
                <p className="truncate text-sm font-medium leading-tight">
                  {secondaryLabel(tx) || tx.description}
                </p>
                {/* Bottom row: date + category */}
                <p className="mt-0.5 text-xs text-muted-foreground truncate">
                  {formatDate(tx.transaction_date)}
                  {tertiaryLabel(tx) && (
                    <span> · {tertiaryLabel(tx)}</span>
                  )}
                </p>
              </div>
              {/* Amount */}
              <span className={cn("shrink-0 text-sm font-mono tabular-nums", amountColor(tx))}>
                {formatCurrency(tx.amount)}
              </span>
            </button>
          ))}
        </div>
      )}

      {/* Pagination */}
      {!isLoading && (
        <Pagination variant="range" page={currentPage} pageSize={PAGE_SIZE} total={sorted.length} onPageChange={setPage} />
      )}

      {/* Drawer */}
      {selected && (() => {
        const idx = paginated.findIndex((t) => t.id === selected.id);
        const prev = idx > 0 ? paginated[idx - 1] : null;
        const next = idx < paginated.length - 1 ? paginated[idx + 1] : null;
        return (
          <TransactionDrawer
            tx={selected}
            onClose={() => setTxId(null)}
            onPrev={prev ? () => setTxId(String(prev.id)) : undefined}
            onNext={next ? () => setTxId(String(next.id)) : undefined}
            onFirst={paginated[0] ? () => setTxId(String(paginated[0].id)) : undefined}
            onLast={paginated.at(-1) ? () => setTxId(String(paginated.at(-1)!.id)) : undefined}
          />
        );
      })()}
    </div>
  );
}

// ── Responsive wrapper ────────────────────────────────────────────────────────
// Renders TransactionList on mobile (<md) and TransactionTable on desktop (md+)

function useIsMobile() {
  const [isMobile, setIsMobile] = useState(() =>
    typeof window !== "undefined" ? window.innerWidth < 768 : false
  );
  useEffect(() => {
    const mq = window.matchMedia("(max-width: 767px)");
    const handler = () => setIsMobile(mq.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);
  return isMobile;
}

export function ResponsiveTransactionView(props: Props) {
  const isMobile = useIsMobile();
  return isMobile ? <TransactionList {...props} /> : <TransactionTable {...props} />;
}
