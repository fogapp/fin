import { useEffect, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, X } from "lucide-react";
import { queries } from "@/api/queries";
import { mutations } from "@/api/mutations";
import { api } from "@/api/client";
import { cn } from "@/lib/utils";
import { ErrorState } from "@/components/PageState";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { Skeleton } from "@/components/ui/skeleton";
import type { Issue, ReconciliationAcceptResult } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

/** Reconciliation findings match on key when the API serializes it, falling
 *  back to source (the engine stamps both). */
function isDriftFinding(issue: Issue): boolean {
  return issue.key?.startsWith("reconciliation:") || issue.source === "reconciliation";
}

const ACCEPT_ALL_DESCRIPTION =
  "This writes a balance-adjustment transaction for each drifting holding so your ledger matches " +
  "what the custodian reports. Adjustments are visible in each account's transaction history and " +
  "can be deleted later. Cost basis uses the latest known price.";

function acceptResultLabel({ status, delta }: ReconciliationAcceptResult): string {
  if (status === "adjusted") return `Adjusted by ${delta > 0 ? "+" : ""}${delta}`;
  if (status === "no_observation") return "No custodian observation to accept";
  return "Already in sync";
}

/** Open holdings-drift findings from the reconciliation engine: ledger vs
 *  custodian disagreements surfaced as dismissable Issues, each acceptable
 *  as a balance adjustment. */
export function ReconciliationInbox({ highlighted = false }: { highlighted?: boolean }) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const { data: issues = [], isLoading, isError, refetch } = useQuery(queries.issues());
  const [results, setResults] = useState<Record<string, string>>({});
  const [bulkNotice, setBulkNotice] = useState<string | null>(null);

  useEffect(() => {
    if (!bulkNotice) return;
    const timer = setTimeout(() => setBulkNotice(null), 4000);
    return () => clearTimeout(timer);
  }, [bulkNotice]);

  const refreshCounters = () => {
    invalidate(qc, keys.issues);
    invalidate(qc, keys.systemHealth); // drift-findings counter
  };

  const dismiss = useMutation({
    mutationFn: (id: string) => api.delete(`/issues/${id}`),
    onSuccess: refreshCounters,
  });

  const accept = useMutation({
    mutationFn: ({ key }: { id: string; key: string }) => mutations.acceptReconciliation(key),
    onSuccess: (result, { id }) => {
      setResults((r) => ({ ...r, [id]: acceptResultLabel(result) }));
      refreshCounters();
    },
  });

  const acceptAll = useMutation({
    mutationFn: () => mutations.acceptAllReconciliation(),
    onSuccess: () => {
      setBulkNotice("Queued — balance adjustments will be written in the background");
      refreshCounters();
    },
  });

  const findings = issues.filter(isDriftFinding);

  async function confirmAcceptAll() {
    const ok = await confirm({
      title: `Accept all ${findings.length} custodian balances?`,
      description: ACCEPT_ALL_DESCRIPTION,
      confirmLabel: "Accept all",
    });
    if (ok) acceptAll.mutate();
  }

  if (isError) {
    return (
      <section className="space-y-2">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Reconciliation</p>
        <div className="rounded-xl border bg-card">
          <ErrorState title="Failed to load reconciliation findings" onRetry={() => refetch()} />
        </div>
      </section>
    );
  }

  return (
    <section className="space-y-2">
      <div className="flex items-center justify-between gap-3">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Reconciliation</p>
        <div className="flex items-center gap-2">
          {bulkNotice && <span className="text-xs text-muted-foreground">{bulkNotice}</span>}
          {findings.length > 0 && (
            <Button
              variant="outline"
              size="xs"
              disabled={acceptAll.isPending}
              onClick={confirmAcceptAll}
              className="text-primary hover:bg-primary/10"
            >
              Accept all ({findings.length})
            </Button>
          )}
        </div>
      </div>

      {isLoading ? (
        <Skeleton className="h-11 rounded-xl" />
      ) : findings.length === 0 ? (
        <div className={cn("rounded-xl border bg-card px-4 py-3 text-sm text-muted-foreground transition-shadow", highlighted && "ring-2 ring-primary")}>
          Your transaction history matches the holdings your brokerages report — no missing or extra positions detected.
        </div>
      ) : (
        <div className={cn("divide-y rounded-xl border bg-card transition-shadow", highlighted && "ring-2 ring-primary")}>
          <p className="px-4 py-3 text-xs leading-relaxed text-muted-foreground">
            These holdings differ between your transaction history and what the custodian reports — usually missing or misclassified transactions.
          </p>
          {findings.map((finding) => (
            <div key={finding.id} className="flex gap-3 px-4 py-3">
              <AlertTriangle size={14} className="mt-0.5 shrink-0 text-warning" />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium">{finding.title}</p>
                {finding.body && (
                  <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">{finding.body}</p>
                )}
                {results[finding.id] && (
                  <p className="mt-1 text-xs font-medium text-positive">{results[finding.id]}</p>
                )}
              </div>
              {finding.key?.startsWith("reconciliation:") && !results[finding.id] && (
                <Button
                  variant="ghost"
                  size="xs"
                  onClick={() => accept.mutate({ id: finding.id, key: finding.key! })}
                  disabled={accept.isPending}
                  className="shrink-0 text-primary hover:bg-primary/10 hover:text-primary"
                  title="Write a balance adjustment so the ledger matches the custodian"
                >
                  Accept balance
                </Button>
              )}
              <button
                onClick={() => dismiss.mutate(finding.id)}
                disabled={dismiss.isPending}
                className="h-fit shrink-0 rounded p-0.5 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:pointer-events-none disabled:opacity-50"
                title="Dismiss"
                aria-label="Dismiss"
              >
                <X size={13} />
              </button>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
