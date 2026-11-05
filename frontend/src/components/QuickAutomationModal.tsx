import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { keepPreviousData, useQuery, useQueryClient } from "@tanstack/react-query";
import { Trash2, AlertTriangle } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogFooter } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import { Field } from "@/components/ui/field";
import { SkeletonList } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/toast";
import { MerchantCombobox } from "@/components/MerchantCombobox";
import { CategoryCombobox } from "@/components/CategoryCombobox";
import { useDebounced } from "@/hooks/useDebounced";
import { refreshTransactionsAfterWorkflowApply } from "@/lib/transactionCache";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import { normalizeDescription } from "@/lib/transactions";
import type { CashTransaction, WorkflowDetail, WorkflowStepInput } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Quick automation modal ────────────────────────────────────────────────────
// In-place dialog for creating a simple "when a transaction like this arrives,
// assign merchant/category/tags" workflow, pre-filled from a transaction.
// Field + operator are fixed for this quick flow; the Advanced link hands the
// same prefill to the full workflow builder.

interface QuickCondition {
  field: "description" | "source";
  operator: "matches" | "equals";
  value: string;
}

const CONDITION_LABELS: Record<QuickCondition["field"], string> = {
  description: "Description matches",
  source: "Source equals",
};

function initialConditions(tx: CashTransaction): QuickCondition[] {
  const source: QuickCondition = { field: "source", operator: "equals", value: tx.source };
  // No descriptor to match on — an empty pattern would match every row.
  if (!tx.description) return [source];
  return [
    // Reference numbers and dates change on every occurrence, so the pattern
    // is built from the descriptor's stable text. A literal "*" would be read
    // as a regex quantifier; "." keeps that position a wildcard.
    { field: "description", operator: "matches", value: (normalizeDescription(tx.description) || tx.description).replaceAll("*", ".") },
    source,
  ];
}

function buildQuickAutomationPayload({ name, conditions, merchantId, categoryId, tagIds, transferAccountId }: {
  name: string;
  conditions: QuickCondition[];
  merchantId: string;
  categoryId: string;
  tagIds: string[];
  transferAccountId?: string;
}): { name: string; trigger_type: string; steps: WorkflowStepInput[] } {
  const actions: WorkflowStepInput[] = [];
  if (merchantId) {
    actions.push({ kind: "action", config: { action_type: "assign_merchant", params: { merchant_id: merchantId } }, children: [] });
  }
  if (categoryId) {
    actions.push({ kind: "action", config: { action_type: "assign_category", params: { category_id: categoryId } }, children: [] });
  }
  if (tagIds.length > 0) {
    actions.push({ kind: "action", config: { action_type: "add_tag", params: { tag_id: tagIds } }, children: [] });
  }
  if (transferAccountId) {
    actions.push({ kind: "action", config: { action_type: "transfer_to_account", params: { account_id: transferAccountId } }, children: [] });
  }
  return {
    name,
    trigger_type: "cash_transaction.created",
    steps: [
      {
        kind: "branch",
        config: {
          match_all: true,
          conditions: conditions.map(({ field, operator, value }) => ({ field, operator, value })),
        },
        children: actions,
      },
    ],
  };
}

export function QuickAutomationModal({ tx, transferAccount, onClose }: {
  tx: CashTransaction;
  /** Prefills a "Link as transfer to this account" action (from LinkTransferModal's
   * "always do this" checkbox). */
  transferAccount?: { id: string; name: string };
  onClose: () => void;
}) {
  const navigate = useNavigate();
  const qc = useQueryClient();

  const [name, setName] = useState(
    transferAccount ? `Transfers to ${transferAccount.name}` : `Auto: ${(tx.description ?? tx.source).slice(0, 30)}`,
  );
  const [conditions, setConditions] = useState<QuickCondition[]>(() => initialConditions(tx));
  const [merchantId, setMerchantId] = useState(transferAccount ? "" : tx.merchant_id ?? "");
  const [categoryId, setCategoryId] = useState(transferAccount ? "" : tx.category_id ?? "");
  const [tagIds, setTagIds] = useState<string[]>([]);
  const [transferAccountId, setTransferAccountId] = useState(transferAccount?.id ?? "");
  const [applyToExisting, setApplyToExisting] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { data: merchants = [] } = useQuery(queries.merchants());
  const { data: categories = [] } = useQuery(queries.categories());
  const { data: tags = [] } = useQuery(queries.tags());

  const hasAction = !!merchantId || !!categoryId || tagIds.length > 0 || !!transferAccountId;
  const canSave = !saving && hasAction && name.trim().length > 0;

  function payload() {
    return buildQuickAutomationPayload({ name: name.trim(), conditions, merchantId, categoryId, tagIds, transferAccountId });
  }

  async function handleSave() {
    setSaving(true);
    setError(null);
    try {
      const workflow = await api.post<WorkflowDetail>("/workflows", payload());
      if (applyToExisting) {
        await api.post<{ status: string }>(`/workflows/${workflow.id}/apply_to_existing`, {});
        refreshTransactionsAfterWorkflowApply(qc);
      }
      invalidate(qc, keys.workflows, keys.cashTransactions);
      // Most of the time nobody wants to open the new workflow, so confirm with a
      // transient toast and get out of the way rather than a success screen.
      toast.success(
        applyToExisting
          ? `Automation "${workflow.name}" created — applying to existing transactions`
          : `Automation "${workflow.name}" created`,
        { action: { label: "View", onClick: () => navigate(`/workflows/${workflow.id}`) } },
      );
      onClose();
    } catch (e) {
      setError((e as Error).message);
      setSaving(false);
    }
  }

  function openAdvanced() {
    const prefill = payload();
    onClose();
    navigate("/workflows/new", { state: { prefill } });
  }

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent size="lg">
        <DialogHeader title="Create automation" />
        <div className="grid grid-cols-1 md:grid-cols-[minmax(0,1fr)_16rem]">
          <div className="space-y-4 p-5">
            <p className="text-xs text-muted-foreground">Runs when a matching transaction arrives</p>

            {/* Name */}
            <Field label="Name" htmlFor="quick-automation-name">
              <Input
                id="quick-automation-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </Field>

            {/* Conditions */}
            <div className="space-y-1.5">
              <p className="text-xs font-medium text-muted-foreground">When</p>
              {conditions.map((c) => (
                <div key={c.field} className="flex items-center gap-2">
                  <span className="w-36 shrink-0 text-xs text-muted-foreground">{CONDITION_LABELS[c.field]}</span>
                  <Input
                    aria-label={CONDITION_LABELS[c.field]}
                    value={c.value}
                    onChange={(e) =>
                      setConditions((prev) => prev.map((p) => p.field === c.field ? { ...p, value: e.target.value } : p))
                    }
                    className="h-8 min-w-0 flex-1 px-2.5 text-xs"
                  />
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label={`Remove ${c.field} condition`}
                    onClick={() => setConditions((prev) => prev.filter((p) => p.field !== c.field))}
                    className="shrink-0 text-destructive hover:bg-destructive/10 hover:text-destructive"
                  >
                    <Trash2 size={13} />
                  </Button>
                </div>
              ))}
            </div>

            {/* Actions */}
            <div className="space-y-2">
              <p className="text-xs font-medium text-muted-foreground">Then</p>
              {transferAccountId && transferAccount && (
                <div className="flex items-center gap-2">
                  <span className="w-36 shrink-0 text-xs text-muted-foreground">Link as transfer</span>
                  <span className="min-w-0 flex-1 truncate rounded-lg border border-primary/30 bg-primary/8 px-3 py-1.5 text-sm text-primary">
                    {transferAccount.name}
                  </span>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label="Remove transfer action"
                    onClick={() => setTransferAccountId("")}
                    className="shrink-0 text-destructive hover:bg-destructive/10 hover:text-destructive"
                  >
                    <Trash2 size={13} />
                  </Button>
                </div>
              )}
              <div className="flex items-center gap-2">
                <span className="w-36 shrink-0 text-xs text-muted-foreground">Assign merchant</span>
                <MerchantCombobox
                  value={merchantId}
                  onChange={setMerchantId}
                  merchants={merchants}
                  placeholder="No merchant"
                  className="flex-1"
                />
              </div>
              <div className="flex items-center gap-2">
                <span className="w-36 shrink-0 text-xs text-muted-foreground">Assign category</span>
                <CategoryCombobox
                  value={categoryId}
                  onChange={setCategoryId}
                  categories={categories}
                  placeholder="No category"
                  className="flex-1"
                />
              </div>
              {tags.length > 0 && (
                <div className="flex items-start gap-2">
                  <span className="w-36 shrink-0 pt-1 text-xs text-muted-foreground">Add tags</span>
                  <div className="flex flex-1 flex-wrap gap-1.5">
                    {tags.map((tag) => {
                      const on = tagIds.includes(tag.id);
                      return (
                        <button
                          key={tag.id}
                          type="button"
                          onClick={() => setTagIds((prev) => on ? prev.filter((id) => id !== tag.id) : [...prev, tag.id])}
                          className={cn(
                            "rounded-full border px-2.5 py-0.5 text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                            on
                              ? "border-primary/30 bg-primary/8 text-primary"
                              : "border-border text-muted-foreground hover:border-primary/30 hover:text-primary"
                          )}
                        >
                          {tag.name}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}
              {!hasAction && (
                <p className="text-xs text-muted-foreground">Pick at least one action to save.</p>
              )}
            </div>

            {/* Apply to existing */}
            <label className="flex items-center gap-2 text-sm cursor-pointer select-none">
              <Checkbox
                checked={applyToExisting}
                onChange={(e) => setApplyToExisting(e.target.checked)}
              />
              Apply to existing transactions
            </label>

            {conditions.length === 0 && (
              <div
                role="alert"
                className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/10 px-3 py-2 text-sm text-warning"
              >
                <AlertTriangle size={15} className="mt-0.5 shrink-0" />
                <p>No conditions — this automation will apply to <strong>every</strong> transaction.</p>
              </div>
            )}

            {error && <p className="text-sm text-destructive">{error}</p>}
          </div>

          <MatchPreview conditions={conditions} />
        </div>

        <DialogFooter className="justify-between">
          <Button
            variant="ghost"
            size="sm"
            onClick={openAdvanced}
            className="text-muted-foreground hover:text-foreground"
          >
            Advanced
          </Button>
          <div className="flex gap-2">
            <Button variant="outline" onClick={onClose} disabled={saving}>Cancel</Button>
            <Button onClick={handleSave} disabled={!canSave}>
              {saving ? "Saving…" : "Create automation"}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ── Live match preview ────────────────────────────────────────────────────────
// Runs the current conditions through the same evaluator workflows execute
// with; debounced while typing, previous results held at reduced opacity.

function MatchPreview({ conditions }: { conditions: { field: string; operator: string; value: string }[] }) {
  const debounced = useDebounced(conditions, 350);

  const { data, isPending, isError, isPlaceholderData } = useQuery({
    ...queries.transactionMatchPreview(
      debounced.map(({ field, operator, value }) => ({ field, operator, value }))
    ),
    placeholderData: keepPreviousData,
  });

  const rows = data?.transactions ?? [];
  const total = data?.total ?? 0;

  return (
    <aside className="border-t bg-muted/20 p-4 space-y-2 md:border-t-0 md:border-l">
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs font-medium text-muted-foreground">Matching transactions</p>
        {data && (
          <span
            className={cn(
              "shrink-0 rounded-full px-2 py-0.5 text-xs font-medium tabular-nums",
              total > 100 ? "bg-destructive/10 text-destructive" : "bg-muted text-muted-foreground"
            )}
          >
            {total.toLocaleString()} match
          </span>
        )}
      </div>

      {isError && (
        <p className="text-xs text-muted-foreground">Preview unavailable.</p>
      )}

      {!isError && isPending && (
        <SkeletonList rows={3} className="space-y-1.5" rowClassName="h-6 rounded-lg" />
      )}

      {!isError && data && (
        rows.length === 0 ? (
          <p className="text-xs text-muted-foreground">No transactions match</p>
        ) : (
          <div className={cn("transition-opacity", isPlaceholderData && "opacity-40")}>
            <div className="divide-y overflow-hidden rounded-lg border bg-card text-xs">
              {rows.map((t) => (
                <div key={t.id} className="flex items-center gap-2 px-2.5 py-1.5">
                  <span className="shrink-0 text-muted-foreground">{formatDate(t.transaction_date)}</span>
                  <span className="min-w-0 flex-1 truncate">{t.description}</span>
                  <span className={cn(
                    "shrink-0 tabular-nums",
                    t.amount < 0 ? "text-foreground" : "text-positive"
                  )}>
                    {formatCurrency(t.amount)}
                  </span>
                </div>
              ))}
            </div>
            {total > rows.length && (
              <p className="mt-1.5 text-xs text-muted-foreground">+{(total - rows.length).toLocaleString()} more</p>
            )}
          </div>
        )
      )}
    </aside>
  );
}
