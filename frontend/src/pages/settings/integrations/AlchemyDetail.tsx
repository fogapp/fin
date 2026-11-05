import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { RefreshCw, CheckCircle, Settings2, Plus, Trash2, History } from "lucide-react";
import { queries } from "@/api/queries";
import { useSyncPolling } from "@/hooks/useSyncPolling";
import { api } from "@/api/client";
import type { AlchemyConfiguration, AlchemySyncFrequency, AlchemyWallet } from "@/api/types";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Select } from "@/components/ui/select";
import { FieldError } from "@/components/ui/field";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/PageState";
import { useConfirm } from "@/components/ui/confirm";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { invalidate, keys } from "@/api/keys";
import { useTestConnection } from "./useTestConnection";
import { TestResultBanner } from "./TestResultBanner";

const NETWORK_OPTIONS = [
  { id: "eth-mainnet", label: "Ethereum" },
  { id: "base-mainnet", label: "Base" },
  { id: "polygon-mainnet", label: "Polygon" },
  { id: "arb-mainnet", label: "Arbitrum" },
  { id: "opt-mainnet", label: "Optimism" },
];

const FREQUENCY_OPTIONS: { value: AlchemySyncFrequency; label: string }[] = [
  { value: "daily", label: "Daily" },
  { value: "every_6_hours", label: "Every 6 hours" },
  { value: "hourly", label: "Hourly" },
  { value: "every_15_minutes", label: "Every 15 minutes" },
  { value: "every_5_minutes", label: "Every 5 minutes" },
  { value: "realtime", label: "Real-time (webhooks)" },
];

const networkLabel = (id: string) =>
  NETWORK_OPTIONS.find((n) => n.id === id)?.label ?? id;

const shortAddress = (address: string) =>
  `${address.slice(0, 6)}…${address.slice(-4)}`;

export function AlchemyDetail({ onEditCredentials }: { onEditCredentials: () => void }) {
  const qc = useQueryClient();
  const confirm = useConfirm();

  const { data: config } = useQuery(queries.alchemyConfiguration());
  const { data: wallets, isLoading, isError, refetch, isFetching } = useQuery(queries.alchemyWallets());

  const [syncing, setSyncing] = useState(false);
  useSyncPolling(syncing, {
    delays: [4000, 10000, 20000, 35000],
    timeoutMs: 40000,
    onPoll: () => refetch(),
    onStop: () => setSyncing(false),
  });

  const testConnection = useTestConnection("/alchemy/configuration");

  const [syncResult, setSyncResult] = useState<string | null>(null);
  const syncWallets = useMutation({
    mutationFn: () => api.post("/alchemy/sync"),
    onSuccess: () => { setSyncResult("Sync queued — updating shortly…"); setSyncing(true); },
    onError: (e: Error) => setSyncResult(`Sync failed: ${e.message}`),
  });

  const removeWallet = useMutation({
    mutationFn: (id: string) => api.delete(`/alchemy/wallets/${id}`),
    onSuccess: () => invalidate(qc, keys.alchemyWallets),
  });

  const backfillWallet = useMutation({
    mutationFn: (id: string) => api.post(`/alchemy/wallets/${id}/backfill`),
    onSuccess: () => {
      invalidate(qc, keys.alchemyWallets);
      setSyncing(true);
    },
  });

  const [adding, setAdding] = useState(false);
  const totalValue = (wallets ?? []).reduce((sum, w) => sum + (w.account?.balance ?? 0), 0);

  return (
    <div>
      {/* Banner */}
      <div className="bg-gradient-to-r from-primary/10 via-primary/5 to-transparent border-b px-8 py-8">
        <div className="flex items-start justify-between">
          <div>
            <div className="flex items-center gap-2 mb-3">
              <Badge variant="success">Connected</Badge>
              <span className="text-xs text-muted-foreground">Portfolio API</span>
            </div>
            <h2 className="text-base font-semibold text-foreground">Alchemy</h2>
            <p className="text-sm text-muted-foreground mt-1">
              On-chain wallet balances · API key: {config?.api_key_set ? "Configured" : "Not set"}
            </p>
          </div>
          {wallets !== undefined && (
            <div className="text-right shrink-0 ml-6">
              <p className="text-4xl font-bold text-foreground tabular-nums">{formatCurrency(totalValue)}</p>
              <p className="text-sm text-muted-foreground">
                across {wallets.length} {wallets.length === 1 ? "wallet" : "wallets"}
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
            onClick={() => { setSyncResult(null); syncWallets.mutate(); }}
            disabled={syncWallets.isPending}
          >
            <RefreshCw size={13} className={syncWallets.isPending ? "animate-spin" : ""} />
            {syncWallets.isPending ? "Syncing…" : "Sync balances"}
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={testConnection.test}
            disabled={testConnection.isPending}
          >
            {testConnection.isPending ? "Testing…" : "Test connection"}
          </Button>
          <Button variant="outline" size="sm" onClick={onEditCredentials}>
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

      {/* Transactions */}
      {config && <TransactionsSection config={config} />}

      {/* Wallets */}
      <div className="px-8 py-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Tracked wallets</p>
            {syncing && <span className="text-tiny text-muted-foreground animate-pulse">Syncing…</span>}
          </div>
          <div className="flex gap-2">
            <Button size="sm" variant="outline" onClick={() => refetch()} disabled={isFetching}>
              <RefreshCw size={13} className={isFetching ? "animate-spin" : ""} />
              Refresh
            </Button>
            <Button size="sm" onClick={() => setAdding(true)}>
              <Plus size={13} />
              Add wallet
            </Button>
          </div>
        </div>

        {adding && (
          <AddWalletForm
            onDone={() => { setAdding(false); setSyncing(true); }}
            onCancel={() => setAdding(false)}
          />
        )}

        {isLoading && <SkeletonList rows={2} rowClassName="h-10 rounded-lg" />}
        {isError && <ErrorState title="Failed to load wallets" onRetry={() => refetch()} />}
        {!isLoading && !isError && (wallets?.length ?? 0) === 0 && !adding && (
          <EmptyState
            title="No wallets tracked yet."
            description="Add a wallet address to sync its on-chain balances."
            className="py-6"
          />
        )}
        {(wallets?.length ?? 0) > 0 && (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-xs text-muted-foreground">
                <th className="pb-2 text-left font-medium">Wallet</th>
                <th className="pb-2 text-left font-medium">Networks</th>
                <th className="pb-2 text-right font-medium">Value</th>
                <th className="pb-2 text-right font-medium">Last synced</th>
                <th className="pb-2" />
              </tr>
            </thead>
            <tbody className="divide-y">
              {wallets!.map((wallet) => (
                <WalletRow
                  key={wallet.id}
                  wallet={wallet}
                  transactionsEnabled={config?.transactions_enabled ?? false}
                  onBackfill={async () => {
                    const ok = await confirm({
                      title: "Backfill transaction history?",
                      description: `Re-scan the full on-chain history of ${wallet.display_name}. Existing transactions are kept; this can take a while for busy wallets.`,
                      confirmLabel: "Backfill",
                    });
                    if (ok) backfillWallet.mutate(wallet.id);
                  }}
                  onRemove={async () => {
                    const ok = await confirm({
                      title: "Remove wallet?",
                      description: `Stop tracking ${wallet.display_name}? Its account and history are kept.`,
                      confirmLabel: "Remove",
                      destructive: true,
                    });
                    if (ok) removeWallet.mutate(wallet.id);
                  }}
                />
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function TransactionsSection({ config }: { config: AlchemyConfiguration }) {
  const qc = useQueryClient();

  const updateConfig = useMutation({
    mutationFn: (patch: { transactions_enabled?: boolean; sync_frequency?: AlchemySyncFrequency }) =>
      api.patch("/alchemy/configuration", { alchemy_configuration: patch }),
    onSuccess: () => invalidate(qc, keys.alchemyConfiguration),
  });

  const realtime = config.sync_frequency === "realtime";
  const realtimeMissingCreds = realtime && (!config.auth_token_set || !config.webhook_base_url);

  return (
    <div className="px-8 py-5 border-b">
      <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Transactions</p>
      <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
        <label className="flex items-center gap-2 text-sm">
          <Checkbox
            checked={config.transactions_enabled}
            onChange={() => updateConfig.mutate({ transactions_enabled: !config.transactions_enabled })}
            disabled={updateConfig.isPending}
          />
          Track on-chain transactions
        </label>
        {config.transactions_enabled && (
          <div className="flex items-center gap-2 text-sm">
            <Label htmlFor="alchemy-sync-frequency" className="text-muted-foreground">Check for new activity</Label>
            <Select
              id="alchemy-sync-frequency"
              value={config.sync_frequency}
              onChange={(e) => updateConfig.mutate({ sync_frequency: e.target.value as AlchemySyncFrequency })}
              disabled={updateConfig.isPending}
            >
              {FREQUENCY_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </Select>
          </div>
        )}
        {config.transactions_enabled && config.transactions_last_synced_at && (
          <span className="text-xs text-muted-foreground">
            Last checked {formatDate(config.transactions_last_synced_at)}
          </span>
        )}
      </div>

      {config.transactions_enabled && realtime && (
        <div className="mt-3 space-y-1.5">
          {realtimeMissingCreds && (
            <p className="text-sm text-destructive">
              Real-time sync needs a Notify auth token and public base URL — set both under "Edit credentials".
            </p>
          )}
          {config.webhooks.length > 0 && (
            <div className="flex flex-wrap gap-2">
              {config.webhooks.map((w) => (
                <span key={w.network} className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Badge variant={w.status === "active" ? "success" : "destructive"}>
                    {networkLabel(w.network)}
                  </Badge>
                  {w.status === "active"
                    ? (w.last_received_at ? `last event ${formatDate(w.last_received_at)}` : "waiting for events")
                    : (w.last_error ?? "error")}
                </span>
              ))}
            </div>
          )}
        </div>
      )}
      {updateConfig.isError && (
        <FieldError className="text-sm mt-2">Failed to update transaction settings.</FieldError>
      )}
    </div>
  );
}

function backfillLabel(sync: AlchemyWallet["syncs"][number]) {
  switch (sync.backfill_status) {
    case "completed": return "History complete";
    case "running":   return `Backfilling… ${sync.backfill_transfer_count.toLocaleString()} transfers`;
    case "failed":    return `Backfill failed${sync.last_error ? `: ${sync.last_error}` : ""}`;
    default:          return "Backfill queued";
  }
}

function WalletRow({ wallet, transactionsEnabled, onRemove, onBackfill }: {
  wallet: AlchemyWallet;
  transactionsEnabled: boolean;
  onRemove: () => void;
  onBackfill: () => void;
}) {
  return (
    <tr>
      <td className="py-2.5">
        <p className="font-medium">{wallet.display_name}</p>
        <p className="text-xs text-muted-foreground font-mono">{shortAddress(wallet.address)}</p>
        {wallet.last_error && (
          <p className="text-xs text-destructive mt-0.5">{wallet.last_error}</p>
        )}
        {transactionsEnabled && wallet.syncs.map((sync) => (
          <p
            key={sync.network}
            className={cn(
              "text-xs mt-0.5",
              sync.backfill_status === "failed" ? "text-destructive" : "text-muted-foreground",
              sync.backfill_status === "running" && "animate-pulse"
            )}
          >
            {networkLabel(sync.network)}: {backfillLabel(sync)}
          </p>
        ))}
      </td>
      <td className="py-2.5 text-muted-foreground">
        {wallet.networks.map(networkLabel).join(", ")}
      </td>
      <td className="py-2.5 text-right tabular-nums font-medium">
        {wallet.account?.balance != null
          ? formatCurrency(wallet.account.balance)
          : <span className="text-muted-foreground">—</span>}
      </td>
      <td className="py-2.5 text-right text-xs text-muted-foreground">
        {wallet.last_synced_at ? formatDate(wallet.last_synced_at) : "—"}
      </td>
      <td className="py-2.5 text-right whitespace-nowrap">
        {transactionsEnabled && (
          <button
            onClick={onBackfill}
            title="Backfill history"
            aria-label={`Backfill history for ${wallet.display_name}`}
            className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <History size={14} />
          </button>
        )}
        <button
          onClick={onRemove}
          title="Remove wallet"
          aria-label={`Remove ${wallet.display_name}`}
          className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-destructive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          <Trash2 size={14} />
        </button>
      </td>
    </tr>
  );
}

function AddWalletForm({ onDone, onCancel }: { onDone: () => void; onCancel: () => void }) {
  const qc = useQueryClient();
  const [address, setAddress] = useState("");
  const [name, setName] = useState("");
  const [networks, setNetworks] = useState<string[]>(["eth-mainnet", "base-mainnet"]);

  const addWallet = useMutation({
    mutationFn: () =>
      api.post("/alchemy/wallets", {
        alchemy_wallet: {
          address: address.trim(),
          ...(name.trim() ? { name: name.trim() } : {}),
          networks,
        },
      }),
    onSuccess: () => {
      invalidate(qc, keys.alchemyWallets);
      onDone();
    },
  });

  const toggleNetwork = (id: string) =>
    setNetworks((prev) => (prev.includes(id) ? prev.filter((n) => n !== id) : [...prev, id]));

  const validAddress = /^0x[0-9a-fA-F]{40}$/.test(address.trim());

  return (
    <form
      onSubmit={(e) => { e.preventDefault(); addWallet.mutate(); }}
      className="mb-6 space-y-4 rounded-lg border bg-muted/30 p-4"
    >
      <div className="space-y-1.5">
        <Label htmlFor="wallet-address">Address</Label>
        <Input
          id="wallet-address"
          type="text"
          placeholder="0x…"
          value={address}
          onChange={(e) => setAddress(e.target.value)}
          className="font-mono text-sm"
          autoComplete="off"
        />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="wallet-name">Name (optional)</Label>
        <Input
          id="wallet-name"
          type="text"
          placeholder="e.g. Main Vault"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
      </div>
      <div className="space-y-1.5">
        <Label>Networks</Label>
        <div className="flex flex-wrap gap-x-4 gap-y-2">
          {NETWORK_OPTIONS.map((n) => (
            <label key={n.id} className="flex items-center gap-1.5 text-sm">
              <Checkbox checked={networks.includes(n.id)} onChange={() => toggleNetwork(n.id)} />
              {n.label}
            </label>
          ))}
        </div>
      </div>
      <div className="flex gap-2">
        <Button type="submit" size="sm" disabled={!validAddress || networks.length === 0 || addWallet.isPending}>
          {addWallet.isPending ? "Adding…" : "Add wallet"}
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={onCancel}>
          Cancel
        </Button>
      </div>
      {addWallet.isError && (
        <FieldError className="text-sm">Failed to add wallet. Check the address and try again.</FieldError>
      )}
    </form>
  );
}
