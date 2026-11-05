import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { RefreshCw, Unlink, CheckCircle, AlertCircle, Settings2, Link2 } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { useConfirm } from "@/components/ui/confirm";
import { ErrorState } from "@/components/PageState";
import { formatDate } from "@/lib/utils";
import { invalidate, keys } from "@/api/keys";
import { usePlaidLinkFlow } from "@/hooks/usePlaidLinkFlow";

function PlaidLinkButton() {
  const { open, canOpen, tokenLoading, tokenError, linking, error } = usePlaidLinkFlow();

  return (
    <div className="flex flex-col gap-1.5">
      <Button
        variant="outline"
        size="sm"
        onClick={open}
        disabled={!canOpen}
      >
        <Link2 size={13} className={tokenLoading ? "animate-pulse" : ""} />
        {linking ? "Linking…" : tokenLoading ? "Preparing…" : "Connect institution"}
      </Button>
      {(tokenError || error) && (
        <p className="text-xs text-destructive">
          {error ?? "Couldn't reach Plaid. Check credentials and try again."}
        </p>
      )}
    </div>
  );
}

export function PlaidDetail({ onEditCredentials }: { onEditCredentials: () => void }) {
  const qc = useQueryClient();
  const confirm = useConfirm();

  const { data: config } = useQuery(queries.plaidConfiguration());
  const { data: items = [], isLoading: itemsLoading, isError: itemsError, refetch: refetchItems } = useQuery(queries.plaidItems());

  const totalAccounts = items.reduce((n, item) => n + item.plaid_accounts.length, 0);

  const syncItem = useMutation({
    mutationFn: (id: string) => api.post(`/plaid/items/${id}/sync`),
    onSuccess: () => invalidate(qc, keys.plaidItems),
  });

  const removeItem = useMutation({
    mutationFn: (id: string) => api.delete(`/plaid/items/${id}`),
    onSuccess: () => invalidate(qc, keys.plaidItems),
  });

  return (
    <div>
      {/* Banner */}
      <div className="bg-gradient-to-r from-primary/10 via-primary/5 to-transparent border-b px-8 py-8">
        <div className="flex items-start justify-between">
          <div>
            <div className="flex items-center gap-2 mb-3">
              <Badge variant="success">Connected</Badge>
              {config && (
                <span className="text-xs text-muted-foreground capitalize">{config.environment}</span>
              )}
            </div>
            <h2 className="text-base font-semibold text-foreground">Plaid</h2>
            <p className="text-sm text-muted-foreground mt-1">Bank &amp; investment account connections</p>
          </div>
          <div className="text-right shrink-0 ml-6">
            <p className="text-4xl font-bold text-foreground tabular-nums">{totalAccounts}</p>
            <p className="text-sm text-muted-foreground">
              {totalAccounts === 1 ? "account" : "accounts"}
            </p>
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="px-8 py-5 border-b">
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Actions</p>
        <div className="flex flex-wrap gap-2">
          <PlaidLinkButton />
          <Button variant="outline" size="sm" onClick={onEditCredentials}>
            <Settings2 size={13} />
            Edit credentials
          </Button>
        </div>
      </div>

      {/* Institutions */}
      <div className="px-8 py-6">
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-4">
          Connected institutions
        </p>
        {itemsLoading && <SkeletonList rows={3} rowClassName="h-16 rounded-lg" />}
        {itemsError && <ErrorState title="Failed to load institutions" onRetry={() => refetchItems()} />}
        {!itemsLoading && !itemsError && items.length === 0 && (
          <EmptyState
            title="No institutions connected yet."
            description="Use Plaid Link to connect a bank or investment account."
            className="py-6"
          />
        )}
        {!itemsLoading && items.length > 0 && (
          <p className="text-xs text-muted-foreground mb-4 leading-relaxed">
            Transaction history on first connect is limited by what each bank exposes — most provide
            up to 24 months, but some (like Charles Schwab) may only offer 90 days. To backfill
            older history, export a CSV from your bank and use the import tool.
          </p>
        )}
        {items.map((item) => (
          <div key={item.id} className="mb-4 rounded-lg border bg-card">
            {/* Institution header */}
            <div className="flex items-center justify-between px-4 py-3 border-b">
              <div className="flex items-center gap-2">
                {item.status === "active"
                  ? <CheckCircle size={14} className="text-positive shrink-0" />
                  : <AlertCircle size={14} className="text-negative shrink-0" />}
                <div>
                  <p className="text-sm font-medium">{item.institution_name}</p>
                  <p className="text-xs text-muted-foreground">
                    Last synced: {item.last_synced_at ? formatDate(item.last_synced_at) : "Never"}
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-2 shrink-0 ml-4">
                <Badge variant={item.status === "active" ? "success" : "destructive"} className="capitalize">
                  {item.status}
                </Badge>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => syncItem.mutate(item.id)}
                  disabled={syncItem.isPending}
                >
                  <RefreshCw size={13} className={syncItem.isPending ? "animate-spin" : ""} />
                  Sync
                </Button>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  className="text-destructive hover:bg-destructive/10 hover:text-destructive"
                  aria-label={`Disconnect ${item.institution_name}`}
                  title="Disconnect"
                  onClick={async () => {
                    if (await confirm({
                      title: `Disconnect ${item.institution_name}?`,
                      confirmLabel: "Disconnect",
                      destructive: true,
                    })) removeItem.mutate(item.id);
                  }}
                  disabled={removeItem.isPending}
                >
                  <Unlink size={13} />
                </Button>
              </div>
            </div>
            {/* Accounts */}
            {item.plaid_accounts.length > 0 && (
              <div className="divide-y">
                {item.plaid_accounts.map((acct) => (
                  <div key={acct.id} className="flex items-center justify-between px-4 py-2.5">
                    <p className="text-sm">{acct.display_name}</p>
                    <div className="flex items-center gap-3 shrink-0 ml-4">
                      <span className="text-xs text-muted-foreground capitalize">{acct.account_type}</span>
                      <Badge variant={acct.linked ? "success" : "outline"} className="text-xs">
                        {acct.linked ? "Linked" : "Unlinked"}
                      </Badge>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
