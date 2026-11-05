import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";
import { clearToken } from "@/api/client";
import { toast } from "@/components/ui/toast";

/** Centralised handler: when any query/mutation hits 401, clear the token
 *  and bounce the user to /login. Without this, pages keep rendering with
 *  "unauthorized" stuck in their error state until the user refreshes. */
export function handleUnauthorized(err: unknown) {
  if ((err as Error)?.message !== "unauthorized") return;
  clearToken();
  if (typeof window !== "undefined" && window.location.pathname !== "/login") {
    window.location.assign("/login");
  }
}

/** Factory shared with the integration test harness so tests exercise the
 *  same QueryCache / MutationCache wiring as production. */
export function createAppQueryClient() {
  return new QueryClient({
    queryCache: new QueryCache({ onError: handleUnauthorized }),
    // Mutations with no local onError still surface failures to the user via a
    // toast — a silent failed save is worse than a generic message.
    mutationCache: new MutationCache({
      onError: (err, _variables, _context, mutation) => {
        handleUnauthorized(err);
        if ((err as Error)?.message === "unauthorized") return;
        if (mutation.options.onError) return;
        toast.error((err as Error)?.message || "Something went wrong. Please try again.");
      },
    }),
    defaultOptions: {
      queries: {
        staleTime: 60_000,
        // Mutations invalidate their query keys explicitly, so focus refetch
        // only re-pulls unchanged data — on the transaction list that meant
        // re-downloading the whole table every time the tab regained focus.
        refetchOnWindowFocus: false,
        retry: (count, err) => (err as Error)?.message === "unauthorized" ? false : count < 2,
      },
    },
  });
}
