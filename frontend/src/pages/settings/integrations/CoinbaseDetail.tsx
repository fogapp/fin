import { useState } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { RefreshCw, CheckCircle, Settings2 } from "lucide-react";
import { queries } from "@/api/queries";
import { useSyncPolling } from "@/hooks/useSyncPolling";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/PageState";
import { formatCurrency } from "@/lib/utils";
import { useTestConnection } from "./useTestConnection";
import { TestResultBanner } from "./TestResultBanner";

export function CoinbaseDetail({ onEditCredentials }: { onEditCredentials: () => void }) {

  const { data: config } = useQuery(queries.coinbaseConfiguration());
  const { data: accounts, isLoading: accountsLoading, isError: accountsError, refetch, isFetching } = useQuery({
    ...queries.coinbaseAccounts(),
    enabled: config?.configured ?? false,
    retry: false,
  });

  const [syncing, setSyncing] = useState(false);
  useSyncPolling(syncing, {
    delays: [4000, 10000, 20000, 35000],
    timeoutMs: 40000,
    onPoll: () => refetch(),
    onStop: () => setSyncing(false),
  });

  const testConnection = useTestConnection("/coinbase/configuration");

  const [syncResult, setSyncResult] = useState<string | null>(null);
  const syncTransactions = useMutation({
    mutationFn: () => api.post("/coinbase/sync"),
    onSuccess: () => { setSyncResult("Sync queued — updating shortly…"); setSyncing(true); },
    onError: (e: Error) => setSyncResult(`Sync failed: ${e.message}`),
  });

  const funded = (accounts?.filter((a) => parseFloat(a.balance ?? "0") > 0) ?? [])
    .sort((a, b) => (b.balance_usd ?? 0) - (a.balance_usd ?? 0));
  const zeroCount = (accounts?.length ?? 0) - funded.length;

  return (
    <div>
      {/* Banner */}
      <div className="bg-gradient-to-r from-primary/10 via-primary/5 to-transparent border-b px-8 py-8">
        <div className="flex items-start justify-between">
          <div>
            <div className="flex items-center gap-2 mb-3">
              <Badge variant="success">Connected</Badge>
              <span className="text-xs text-muted-foreground">Advanced Trade API</span>
            </div>
            <h2 className="text-base font-semibold text-foreground">Coinbase</h2>
            <p className="text-sm text-muted-foreground mt-1">
              API key: {config?.api_key_id_set ? "Configured" : "Not set"}
            </p>
          </div>
          {accounts !== undefined && (
            <div className="text-right shrink-0 ml-6">
              <p className="text-4xl font-bold text-foreground tabular-nums">{funded.length}</p>
              <p className="text-sm text-muted-foreground">
                {funded.length === 1 ? "funded account" : "funded accounts"}
              </p>
            </div>
          )}
        </div>
      </div>

      {/* Actions */}
      <div className="px-8 py-5 border-b">
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Actions</p>
        <div className="flex flex-wrap gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => { setSyncResult(null); syncTransactions.mutate(); }}
            disabled={syncTransactions.isPending}
          >
            <RefreshCw size={13} className={syncTransactions.isPending ? "animate-spin" : ""} />
            {syncTransactions.isPending ? "Syncing…" : "Sync transactions"}
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={testConnection.test}
            disabled={testConnection.isPending}
          >
            {testConnection.isPending ? "Testing…" : "Test connection"}
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={onEditCredentials}
          >
            <Settings2 size={13} />
            Edit credentials
          </Button>
        </div>

        <TestResultBanner result={testConnection.result} />
        {syncResult && (
          <div className="flex items-center gap-2 rounded-md px-3 py-2 text-sm mt-3 bg-muted text-muted-foreground">
            <CheckCircle size={14} />
            {syncResult}
          </div>
        )}
      </div>

      {/* Accounts */}
      <div className="px-8 py-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Accounts</p>
            {syncing && <span className="text-tiny text-muted-foreground animate-pulse">Syncing…</span>}
          </div>
          <Button size="sm" variant="outline" onClick={() => refetch()} disabled={isFetching}>
            <RefreshCw size={13} className={isFetching ? "animate-spin" : ""} />
            Refresh
          </Button>
        </div>

        {accountsLoading && <SkeletonList rows={3} rowClassName="h-10 rounded-lg" />}
        {accountsError && <ErrorState title="Failed to load accounts" onRetry={() => refetch()} />}
        {!accountsLoading && !accountsError && funded.length === 0 && (
          <EmptyState title="No accounts with a balance found." className="py-6" />
        )}
        {funded.length > 0 && (
          <>
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-xs text-muted-foreground">
                  <th className="pb-2 text-left font-medium">Account</th>
                  <th className="pb-2 text-right font-medium">Balance</th>
                  <th className="pb-2 text-right font-medium">USD Value</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {funded.map((acct) => (
                  <tr key={acct.id}>
                    <td className="py-2.5">
                      <p className="font-medium">{acct.name}</p>
                      <p className="text-xs text-muted-foreground">{acct.currency}</p>
                    </td>
                    <td className="py-2.5 text-right tabular-nums text-muted-foreground">
                      {parseFloat(acct.balance!).toLocaleString(undefined, { minimumFractionDigits: 3, maximumFractionDigits: 3 })}
                    </td>
                    <td className="py-2.5 text-right tabular-nums font-medium">
                      {acct.balance_usd != null
                        ? formatCurrency(acct.balance_usd)
                        : <span className="text-muted-foreground">—</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {zeroCount > 0 && (
              <p className="mt-3 text-xs text-muted-foreground">
                {zeroCount} {zeroCount === 1 ? "account" : "accounts"} with zero balance hidden
              </p>
            )}
          </>
        )}
      </div>
    </div>
  );
}
