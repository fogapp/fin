import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";
import type { CashTransaction } from "@/api/types";
import { invalidateTransactionAggregates, updateTransactionInCaches } from "@/lib/transactionCache";

export type TransactionPatch = Partial<Pick<CashTransaction, "merchant_id" | "category_id" | "memo" | "budget_excluded">>;

/**
 * Every write the transaction drawer and detail page make against one row.
 * Single-row edits patch the returned row into each cached list in place (a
 * prefix invalidation would refetch the whole paged history) and mark derived
 * aggregates stale; transfer operations change both legs of a pair, so they
 * keep full invalidation.
 */
export function useTransactionMutations(txId: string) {
  const qc = useQueryClient();

  const onRowUpdated = (updated: CashTransaction) => {
    updateTransactionInCaches(qc, updated);
    invalidateTransactionAggregates(qc);
  };
  const onTagChange = (updated: CashTransaction) => {
    updateTransactionInCaches(qc, updated);
    invalidate(qc, keys.tags);
  };
  const onTransferChange = () => invalidate(qc, keys.transfers, keys.cashTransactions, keys.transactionContext);

  const patch = useMutation({
    mutationFn: (updates: TransactionPatch) => api.patch<CashTransaction>(`/cash_transactions/${txId}`, updates),
    onSuccess: onRowUpdated,
  });

  const addTag = useMutation({
    mutationFn: (tagId: string) => api.post<CashTransaction>(`/cash_transactions/${txId}/add_tag`, { tag_id: tagId }),
    onSuccess: onTagChange,
  });

  const removeTag = useMutation({
    mutationFn: (tagId: string) => api.delete<CashTransaction>(`/cash_transactions/${txId}/remove_tag?tag_id=${tagId}`),
    onSuccess: onTagChange,
  });

  const createAndAddTag = useMutation({
    mutationFn: async (name: string) => {
      const tag = await api.post<{ id: string; name: string }>("/tags", { name });
      return api.post<CashTransaction>(`/cash_transactions/${txId}/add_tag`, { tag_id: tag.id });
    },
    onSuccess: onTagChange,
  });

  const confirmTransfer = useMutation({
    mutationFn: (transferId: string) => api.post(`/transfers/${transferId}/confirm`, {}),
    onSuccess: onTransferChange,
  });

  const toggleIncludeInSpend = useMutation({
    mutationFn: ({ id, include_in_spend }: { id: string; include_in_spend: boolean }) =>
      api.patch(`/transfers/${id}`, { include_in_spend }),
    onSuccess: onTransferChange,
  });

  const unlinkTransfer = useMutation({
    mutationFn: (transferId: string) => api.delete(`/transfers/${transferId}`),
    onSuccess: onTransferChange,
  });

  // Other rows (a merchant's uncategorized history) brought in line with this
  // one — a structural change across many rows, so full invalidation.
  const applyToOthers = useMutation({
    mutationFn: (body: { ids: string[]; category_id?: string; merchant_id?: string }) =>
      api.post<{ updated: number }>("/cash_transactions/bulk_update", body),
    onSuccess: () => {
      invalidate(qc, keys.cashTransactions);
      invalidateTransactionAggregates(qc);
    },
  });

  const destroy = useMutation({
    mutationFn: () => api.delete(`/cash_transactions/${txId}`),
    onSuccess: () => {
      invalidate(qc, keys.cashTransactions);
      invalidateTransactionAggregates(qc);
    },
  });

  return { patch, addTag, removeTag, createAndAddTag, confirmTransfer, toggleIncludeInSpend, unlinkTransfer, applyToOthers, destroy };
}
