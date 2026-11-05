import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { mutations } from "@/api/mutations";
import { api } from "@/api/client";
import { formatDate } from "@/lib/utils";
import { AlertCircle, AlertTriangle, Check, Info, Play, Trash2, X } from "lucide-react";
import { SkeletonList } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { useConfirm } from "@/components/ui/confirm";
import { ErrorState } from "@/components/PageState";
import { useState } from "react";
import type { Issue } from "@/api/types";
import { invalidate, keys } from "@/api/keys";
import { conversionIdFromIssueKey, useSecurityConversionActions } from "@/hooks/mutations/useSecurityConversionActions";

function SeverityIcon({ severity }: { severity: Issue["severity"] }) {
  if (severity === "error")   return <AlertCircle   size={14} className="text-destructive shrink-0 mt-0.5" />;
  if (severity === "warning") return <AlertTriangle size={14} className="text-warning shrink-0 mt-0.5" />;
  return                             <Info          size={14} className="text-primary shrink-0 mt-0.5" />;
}

/**
 * A suggested security conversion is a question, not a notice: confirming it
 * changes how history is valued, dismissing it stops it being suggested.
 */
function ConversionActions({ issueKey }: { issueKey: string | null }) {
  const conversionId = conversionIdFromIssueKey(issueKey);
  const { confirm, dismiss } = useSecurityConversionActions();
  if (!conversionId) return null;

  const busy = confirm.isPending || dismiss.isPending;
  return (
    <div className="mt-2 flex items-center gap-2">
      <Button size="sm" onClick={() => confirm.mutate(conversionId)} disabled={busy}>
        <Check size={13} /> Confirm conversion
      </Button>
      <Button variant="outline" size="sm" onClick={() => dismiss.mutate(conversionId)} disabled={busy}>
        <X size={13} /> Not a conversion
      </Button>
    </div>
  );
}

export function IssuesSection() {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const { data: issues = [], isLoading, isError, refetch } = useQuery(queries.issues());
  const { data: workflows = [] } = useQuery(queries.workflows());
  const [ran, setRan] = useState(false);

  // The audit runs as a seeded scheduled workflow now.
  const auditWorkflow = workflows.find((w) => w.seed_key === "system_audit") ?? null;

  const dismiss = useMutation({
    mutationFn: (id: string) => api.delete(`/issues/${id}`),
    onSuccess: () => invalidate(qc, keys.issues),
  });

  const runAudit = useMutation({
    mutationFn: () => api.post(`/workflows/${auditWorkflow!.id}/run_now`, {}),
    onSuccess: () => {
      setRan(true);
      setTimeout(() => {
        setRan(false);
        invalidate(qc, keys.issues);
      }, 4000);
    },
  });

  const [dismissedCount, setDismissedCount] = useState<number | null>(null);
  const dismissAll = useMutation({
    mutationFn: () => mutations.dismissAllIssues(),
    onSuccess: ({ dismissed }) => {
      setDismissedCount(dismissed);
      setTimeout(() => setDismissedCount(null), 4000);
      invalidate(qc, keys.issues);
    },
  });

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-sm font-medium">Issues</p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Warnings and errors detected by the daily audit. Dismiss an issue once you've reviewed it — it will reappear if the problem persists.
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          {dismissedCount != null ? (
            <span className="flex items-center gap-1 text-xs text-muted-foreground">
              <Check size={13} className="text-positive" /> {dismissedCount} dismissed
            </span>
          ) : issues.length > 0 && (
            <Button
              variant="outline"
              size="sm"
              onClick={async () => {
                const ok = await confirm({
                  title: `Dismiss all ${issues.length} open issues?`,
                  description: "Issues whose cause still exists will reappear on the next audit.",
                  confirmLabel: "Dismiss all",
                  destructive: true,
                });
                if (ok) dismissAll.mutate();
              }}
              disabled={dismissAll.isPending}
            >
              <Trash2 size={13} /> Clear all
            </Button>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={() => runAudit.mutate()}
            disabled={runAudit.isPending || ran || !auditWorkflow}
            title={auditWorkflow ? undefined : "System audit workflow not found"}
          >
            {ran
              ? <><AlertCircle size={13} className="text-positive" /> Queued</>
              : <><Play size={13} className={runAudit.isPending ? "animate-pulse" : ""} /> Run audit</>}
          </Button>
        </div>
      </div>

      {isLoading ? (
        <SkeletonList rows={3} />
      ) : isError ? (
        <ErrorState title="Failed to load issues" onRetry={() => refetch()} />
      ) : issues.length === 0 ? (
        <div className="rounded-xl border bg-card">
          <EmptyState icon={Check} title="No active issues — everything looks good." className="py-8" />
        </div>
      ) : (
        <div className="rounded-xl border divide-y">
          {issues.map((issue) => (
            <div key={issue.id} className="flex gap-3 px-4 py-3">
              <SeverityIcon severity={issue.severity} />
              <div className="flex-1 min-w-0">
                <div className="flex items-start justify-between gap-3">
                  <p className="text-sm font-medium">{issue.title}</p>
                  <button
                    onClick={() => dismiss.mutate(issue.id)}
                    disabled={dismiss.isPending}
                    className="shrink-0 rounded p-0.5 text-muted-foreground hover:bg-accent hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                    title="Dismiss"
                    aria-label="Dismiss issue"
                  >
                    <X size={13} />
                  </button>
                </div>
                {issue.body && (
                  <pre className="mt-1 whitespace-pre-wrap text-xs text-muted-foreground font-sans leading-relaxed">
                    {issue.body}
                  </pre>
                )}
                <ConversionActions issueKey={issue.key} />
                <div className="mt-1.5 flex items-center gap-2 text-xs text-muted-foreground">
                  {issue.source && <span className="rounded bg-muted px-1.5 py-0.5 font-mono">{issue.source}</span>}
                  <span>{formatDate(issue.created_at)}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
