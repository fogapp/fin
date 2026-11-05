import { useMemo } from "react";
import { usePagination } from "@/hooks/usePagination";
import type { ActiveFilter, GroupByKey, SortOption } from "@/components/FilterBar";
import type { CashTransaction } from "@/api/types";
import {
  applyFilters,
  applyTransferVisibility,
  searchTransactions,
  sortTransactions,
} from "@/lib/transactionTable";

interface Options {
  filters: ActiveFilter[];
  matchAll: boolean;
  showTransfers: boolean;
  primarySort: SortOption;
  secondarySort: SortOption | null;
  groupBy: GroupByKey;
  searchQuery: string;
  page: number;
  pageSize: number;
}

/**
 * The row pipeline shared by the desktop table and the mobile list:
 * transfer visibility → filters → sort → search → page. Keeping it in one
 * place is what stops the two views disagreeing about which rows a page
 * shows (drill-down filters, hidden transfers).
 */
export function useTransactionRows(
  transactions: CashTransaction[],
  { filters, matchAll, showTransfers, primarySort, secondarySort, groupBy, searchQuery, page, pageSize }: Options,
) {
  const sorted = useMemo(() => {
    const visible = applyTransferVisibility(transactions, showTransfers);
    const filtered = applyFilters(visible, filters, matchAll);
    return sortTransactions(filtered, { primarySort, secondarySort, groupBy });
  }, [transactions, filters, matchAll, primarySort, secondarySort, groupBy, showTransfers]);

  // Search filters the pre-sorted array — it never changes order, so typing
  // skips the expensive sort entirely.
  const searched = useMemo(
    () => searchTransactions(sorted, searchQuery),
    [sorted, searchQuery],
  );

  const { page: currentPage, pageItems: paginated, totalPages } = usePagination(searched, page, pageSize);

  return { sorted, searched, paginated, totalPages, page: currentPage };
}
