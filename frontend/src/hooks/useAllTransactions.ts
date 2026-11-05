import { useMemo } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { api } from "@/api/client";
import type { CashTransaction } from "@/api/types";
import { keys } from "@/api/keys";

const PAGE_SIZE = 1000;
// Pages fetched per parallel round once the first page proves there's more.
const TAIL_CONCURRENCY = 4;

/**
 * Loads the full transaction set: the first page renders after one bounded
 * request, then the remainder is fetched in parallel rounds behind it (the
 * old implementation paged strictly serially — 20k rows meant 20 sequential
 * round-trips). The accumulated array feeds TransactionTable, whose
 * filtering/search stay client-side and therefore need the complete set
 * eventually — just not before first paint.
 *
 * Both query keys start with "cash_transactions" so existing prefix
 * invalidations from mutations also refresh this cache.
 */
export function useAllTransactions(filters: Record<string, string>) {
  const fetchPage = (offset: number, signal?: AbortSignal) => {
    const params = new URLSearchParams({
      ...filters,
      limit: String(PAGE_SIZE),
      offset: String(offset),
    });
    // Threading the abort signal lets navigation / filter changes cancel
    // in-flight page fetches instead of letting the whole stream finish.
    return api.get<CashTransaction[]>(`/cash_transactions?${params}`, { signal });
  };

  const first = useQuery({
    queryKey: [...keys.cashTransactions, "paged", filters],
    queryFn: ({ signal }) => fetchPage(0, signal),
    staleTime: 5 * 60 * 1000,
    // Server-filter changes (tag_id/account_id) produce a new query key;
    // keep the previous rows on screen instead of flashing a skeleton.
    placeholderData: keepPreviousData,
  });

  const firstPageFull = !first.isPlaceholderData && first.data?.length === PAGE_SIZE;

  const rest = useQuery({
    queryKey: [...keys.cashTransactions, "paged_rest", filters],
    // Never page ahead off placeholder data — it belongs to the previous key.
    enabled: firstPageFull,
    queryFn: async ({ signal }) => {
      const pages: CashTransaction[][] = [];
      let offset = PAGE_SIZE;
      for (;;) {
        const round = await Promise.all(
          Array.from({ length: TAIL_CONCURRENCY }, (_, i) => fetchPage(offset + i * PAGE_SIZE, signal)),
        );
        pages.push(...round);
        // A short (or empty) page inside the round means we've passed the end.
        if (round.some((p) => p.length < PAGE_SIZE)) break;
        offset += TAIL_CONCURRENCY * PAGE_SIZE;
      }
      return pages.flat();
    },
    staleTime: 5 * 60 * 1000,
  });

  const transactions = useMemo(() => {
    const head = first.data ?? [];
    // Only append tail rows that belong to the same filters as the head —
    // while the head is placeholder data (previous key), the tail is gated
    // off; while the tail refetches for a new key, show the head alone.
    if (!firstPageFull || rest.data === undefined) return head;
    return head.concat(rest.data);
  }, [first.data, firstPageFull, rest.data]);

  return {
    transactions,
    /** True until the first page arrives. */
    isLoading: first.isLoading,
    isError: first.isError,
    refetch: first.refetch,
    /** True while later pages are still streaming in (or while previous-key
     *  placeholder rows are shown during a server-filter change). */
    isFetchingAll: first.isPlaceholderData || (firstPageFull && rest.data === undefined) || rest.isFetching,
  };
}
