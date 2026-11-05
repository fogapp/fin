import type { QueryClient } from "@tanstack/react-query";
import type { CashTransaction } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Single-row cache patching ─────────────────────────────────────────────────
// Every cash-transaction PATCH/tag endpoint returns the updated row. Instead of
// invalidating the whole ["cash_transactions"] prefix (which forces the full
// ledger in useAllTransactions to refetch EVERY 1000-row page), single-row
// mutations patch the row in place across all cached list shapes:
//
//   ["cash_transactions", <filters|scope>, ...]  → CashTransaction[]
//     (includes useAllTransactions' "paged" / "paged_rest" entries)
//   ["cash_transactions", id]                    → CashTransaction
//   ["cash_transactions", "match_preview", ...]  → { transactions, total }
//
// Trade-off: membership in scoped lists (e.g. a category drill-down after the
// row's category changed) stays stale until the query's normal staleTime
// expires — the row content itself is always fresh. Full invalidation remains
// reserved for bulk/structural operations (bulk apply, transfer linking).

function replaceInList(list: CashTransaction[], updated: CashTransaction): CashTransaction[] {
  let changed = false;
  const next = list.map((t) => {
    if (t.id !== updated.id) return t;
    changed = true;
    return updated;
  });
  return changed ? next : list;
}

/**
 * Replace the returned row by id across every cached query under the
 * ["cash_transactions"] prefix. Falls back to prefix invalidation when the
 * response is not a recognizable transaction row.
 */
export function updateTransactionInCaches(qc: QueryClient, updated: CashTransaction | null | undefined) {
  if (!updated || typeof updated !== "object" || !updated.id) {
    // Defensive: the endpoint didn't hand back the updated row — refetch.
    invalidate(qc, keys.cashTransactions);
    return;
  }

  qc.setQueriesData<unknown>({ queryKey: keys.cashTransactions }, (data: unknown) => {
    if (!data) return data;

    // Flat list queries (index, account/tag/merchant/category scopes, filter).
    if (Array.isArray(data)) return replaceInList(data as CashTransaction[], updated);

    if (typeof data === "object") {
      const d = data as Record<string, unknown>;

      // Match-preview shape ({ transactions, total }).
      if (Array.isArray(d.transactions)) {
        const next = replaceInList(d.transactions as CashTransaction[], updated);
        return next !== d.transactions ? { ...d, transactions: next } : data;
      }

      // Detail entry (["cash_transactions", id]).
      if ((d as { id?: string }).id === updated.id) return updated;
    }

    return data;
  });
}

// Aggregate views derived from transaction data. Invalidation uses the default
// refetchType ("active"): queries visible right now refetch immediately, while
// everything else is just marked stale and refetches on its next mount — so a
// single-row edit never storms every cached page.
const TRANSACTION_AGGREGATE_KEYS = [
  keys.dashboard,
  keys.cashflow,
  keys.budget,
  keys.categories,
  keys.merchants,
  keys.subscriptions,
  keys.stats,
  keys.transactionContext,
];

/** Mark transaction-derived aggregates stale after a single-row edit. */
export function invalidateTransactionAggregates(qc: QueryClient) {
  invalidate(qc, ...TRANSACTION_AGGREGATE_KEYS);
}

// Applying a workflow to existing transactions runs as a background job, so an
// immediate refetch lands before the job has touched anything. Refetch once more
// after a short delay so the table shows the workflow's effect.
export const WORKFLOW_APPLY_REFRESH_DELAY_MS = 3000;

/** Refresh transactions (and their aggregates) once a queued workflow run has had time to finish. */
export function refreshTransactionsAfterWorkflowApply(qc: QueryClient) {
  setTimeout(() => {
    invalidate(qc, keys.cashTransactions);
    invalidateTransactionAggregates(qc);
  }, WORKFLOW_APPLY_REFRESH_DELAY_MS);
}
