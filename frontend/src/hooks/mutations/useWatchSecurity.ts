import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";

export interface WatchTarget {
  ticker: string;
  name?: string | null;
  instrument_class?: string;
}

/**
 * Add a security to the watchlist or drop it. Both refresh the ["securities"]
 * prefix, which covers the market list and every security's detail page.
 */
export function useWatchSecurity({ onWatched }: { onWatched?: (ticker: string) => void } = {}) {
  const qc = useQueryClient();
  const refresh = () => invalidate(qc, keys.securities);

  const watch = useMutation({
    mutationFn: ({ ticker, name, instrument_class }: WatchTarget) =>
      api.post("/market/watch", { ticker, name: name ?? undefined, instrument_class }),
    onSuccess: (_, target) => {
      onWatched?.(target.ticker);
      return refresh();
    },
  });

  const unwatch = useMutation({
    mutationFn: (ticker: string) => api.delete(`/market/${ticker}/unwatch`),
    onSuccess: refresh,
  });

  return { watch, unwatch };
}
