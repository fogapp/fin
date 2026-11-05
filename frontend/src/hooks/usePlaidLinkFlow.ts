import { useCallback, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { usePlaidLink } from "react-plaid-link";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";
import { queries } from "@/api/queries";
import type { PlaidItem } from "@/api/types";

/**
 * The whole Plaid Link round trip: fetch a link token, open Link, exchange the
 * public token for a Plaid item, and refresh items and accounts. `error` holds
 * the latest exchange failure or Link exit reason; `open()` clears it.
 */
export function usePlaidLinkFlow({ onLinked }: { onLinked?: (item: PlaidItem) => void } = {}) {
  const qc = useQueryClient();
  const [error, setError] = useState<string | null>(null);

  const { data: tokenData, isLoading: tokenLoading, isError: tokenError } = useQuery(queries.plaidLinkToken());

  const exchange = useMutation({
    mutationFn: (public_token: string) => api.post<PlaidItem>("/plaid/items", { public_token }),
    onSuccess: (item) => {
      setError(null);
      invalidate(qc, keys.plaidItems, keys.accounts);
      onLinked?.(item);
    },
    onError: (e: Error) => setError(e.message),
  });

  // Plaid Link keeps the first onSuccess it sees; `mutate` is stable across renders.
  const { mutate } = exchange;
  const onSuccess = useCallback((public_token: string) => mutate(public_token), [mutate]);

  const { open, ready } = usePlaidLink({
    token: tokenData?.link_token ?? null,
    onSuccess,
    onExit: (err) => {
      if (err) setError(err.display_message || err.error_message || "Plaid Link closed");
    },
  });

  return {
    open: () => { setError(null); open(); },
    canOpen: ready && !tokenLoading && !exchange.isPending && !!tokenData?.link_token,
    tokenLoading,
    tokenError,
    linking: exchange.isPending,
    error,
  };
}
