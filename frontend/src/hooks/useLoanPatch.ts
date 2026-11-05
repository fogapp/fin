import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";

/**
 * PATCH /loans/:id. Always invalidates the whole ["loans"] prefix: the list
 * shows current_balance, which moves with the anchor, the payment and the
 * interest-only flag — invalidating only the detail left the list stale.
 */
export function useLoanPatch(
  loanId: string,
  { onSuccess, onError }: { onSuccess?: () => void; onError?: (e: Error) => void } = {},
) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: Record<string, unknown>) => api.patch(`/loans/${loanId}`, body),
    onSuccess: () => {
      invalidate(qc, keys.loans);
      onSuccess?.();
    },
    onError,
  });
}
