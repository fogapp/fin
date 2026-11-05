import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, Check, Copy, Pencil, Repeat, Sparkles, Trash2, Zap } from "lucide-react";
import { queries } from "@/api/queries";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { useConfirm } from "@/components/ui/confirm";
import { toast } from "@/components/ui/toast";
import { MerchantCombobox } from "@/components/MerchantCombobox";
import { CategoryCombobox } from "@/components/CategoryCombobox";
import { QuickAutomationModal } from "@/components/QuickAutomationModal";
import { TransactionTags } from "@/components/transaction/TransactionTags";
import { TransferTools } from "@/components/transaction/TransferTools";
import { ActivityRow } from "@/pages/activity/ActivityRow";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import { normalizeDescription } from "@/lib/transactions";
import { useTransactionMutations } from "@/hooks/mutations/useTransactionMutations";
import type { CashTransaction, TransactionContext } from "@/api/types";
import { canTrackAsSubscription, categorySuggestion, relativeDays, roughRhythm, spendReason, uncategorizedPeers, peerLabel } from "./insights";
import { TrackSubscriptionDialog } from "./TrackSubscriptionDialog";

// ── Manage rail ───────────────────────────────────────────────────────────────
// Every tool for acting on the row, in one panel beside the story: first the
// decisions the context says are waiting (a likely duplicate, a category the
// merchant's other charges agree on), then the row's details, how it counts,
// automating it, and the raw record. Each tool carries the context it needs
// to be decided right there.

export function ManageRail({ tx, ctx }: { tx: CashTransaction; ctx: TransactionContext | undefined }) {
  return (
    <aside aria-label="Manage transaction" className="divide-y rounded-xl border bg-card text-card-foreground shadow-sm">
      {ctx ? <Decisions tx={tx} ctx={ctx} /> : <div className="p-4"><Skeleton className="h-16 rounded-lg" /></div>}
      <Details tx={tx} />
      <Counting tx={tx} ctx={ctx} />
      <Automate tx={tx} ctx={ctx} />
      <Record tx={tx} />
    </aside>
  );
}

function Group({ title, children, className }: { title: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("space-y-3 p-4", className)}>
      <p className="text-caption font-medium uppercase tracking-wide text-muted-foreground">{title}</p>
      {children}
    </div>
  );
}

// ── Decisions ─────────────────────────────────────────────────────────────────

function Decisions({ tx, ctx }: { tx: CashTransaction; ctx: TransactionContext }) {
  const navigate = useNavigate();
  const confirm = useConfirm();
  const { patch, applyToOthers, destroy } = useTransactionMutations(tx.id);
  const [appliedTo, setAppliedTo] = useState<string | null>(null);

  const dup = ctx.duplicates[0];
  const suggestion = categorySuggestion(ctx);
  const peers = uncategorizedPeers(tx, ctx);
  const showApply = peers.length > 0 && appliedTo !== tx.category_id;

  if (!dup && !suggestion && !showApply) return null;

  async function deleteDuplicate() {
    const ok = await confirm({
      title: "Delete this transaction?",
      description: "Keep the other copy. If this one came from an import or a bank sync, re-running it may bring it back.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    destroy.mutate(undefined, {
      onSuccess: () => { toast.success("Duplicate deleted"); navigate(`/transactions/${dup!.id}`, { replace: true }); },
    });
  }

  return (
    <Group title="Needs a decision" className="bg-muted/30 first:rounded-t-xl">
      {dup && (
        <Decision icon={<Copy size={14} />} tone="warning">
          <p>
            Possible duplicate: the same {formatCurrency(Math.abs(dup.amount))} charge on {dup.account_name ?? "this account"}, {relativeDays(dup.date_diff)}.
          </p>
          <div className="flex flex-wrap gap-2">
            <Button size="xs" variant="outline" onClick={() => navigate(`/transactions/${dup.id}`)}>
              Compare
            </Button>
            <Button size="xs" variant="outline" className="text-destructive" onClick={deleteDuplicate} disabled={destroy.isPending}>
              <Trash2 size={12} />
              Delete this one
            </Button>
          </div>
        </Decision>
      )}

      {suggestion && (
        <Decision icon={<Sparkles size={14} />}>
          <p>
            {suggestion.count} of {suggestion.of} other {peerLabel(ctx)} charges are <strong className="font-medium">{suggestion.category_name}</strong>
            {tx.category_name ? <>, not {tx.category_name}.</> : "."}
          </p>
          <Button size="xs" onClick={() => patch.mutate({ category_id: suggestion.category_id })} disabled={patch.isPending}>
            Use {suggestion.category_name}
          </Button>
        </Decision>
      )}

      {showApply && !suggestion && (
        <Decision icon={<Check size={14} />}>
          <p>
            {peers.length} other {peerLabel(ctx)} charge{peers.length === 1 ? " has" : "s have"} no category.
          </p>
          <Button
            size="xs"
            variant="outline"
            disabled={applyToOthers.isPending}
            onClick={() => applyToOthers.mutate(
              { ids: peers, category_id: tx.category_id! },
              { onSuccess: (r) => { setAppliedTo(tx.category_id); toast.success(`${tx.category_name} applied to ${r.updated} transaction${r.updated === 1 ? "" : "s"}`); } },
            )}
          >
            Make them {tx.category_name} too
          </Button>
        </Decision>
      )}
    </Group>
  );
}

function Decision({ icon, tone, children }: { icon: React.ReactNode; tone?: "warning"; children: React.ReactNode }) {
  return (
    <div className="flex gap-2.5 text-sm">
      <span className={cn("mt-0.5 shrink-0", tone === "warning" ? "text-warning" : "text-primary")} aria-hidden>{icon}</span>
      <div className="min-w-0 flex-1 space-y-2">{children}</div>
    </div>
  );
}

// ── Details ───────────────────────────────────────────────────────────────────

function Details({ tx }: { tx: CashTransaction }) {
  const { patch } = useTransactionMutations(tx.id);
  const [editing, setEditing] = useState<"merchant" | "category" | null>(null);
  const [memo, setMemo] = useState(tx.memo ?? "");
  const [prevId, setPrevId] = useState(tx.id);
  if (prevId !== tx.id) { setPrevId(tx.id); setMemo(tx.memo ?? ""); setEditing(null); }

  const { data: merchants = [] } = useQuery({ ...queries.merchants(), enabled: editing === "merchant" });
  const { data: categories = [] } = useQuery({ ...queries.categories(), enabled: editing === "category" });

  return (
    <Group title="Details">
      <dl className="space-y-2.5 text-sm">
        <EditRow
          label="Merchant"
          editing={editing === "merchant"}
          onEdit={() => setEditing("merchant")}
          onCancel={() => setEditing(null)}
          onClear={tx.merchant_id ? () => { patch.mutate({ merchant_id: null }); setEditing(null); } : undefined}
          value={tx.merchant_id
            ? <Link to={`/merchants#id=${tx.merchant_id}`} className="hover:underline">{tx.merchant_name}</Link>
            : null}
          editor={
            <MerchantCombobox
              value={tx.merchant_id ?? ""}
              onChange={(id) => {
                // Fires "" while typing to search — only a pick saves.
                if (!id) return;
                patch.mutate({ merchant_id: id });
                setEditing(null);
              }}
              merchants={merchants}
              placeholder="Search or create merchant…"
              className="flex-1"
              autoFocus
              onClose={() => setEditing(null)}
            />
          }
        />
        <EditRow
          label="Category"
          editing={editing === "category"}
          onEdit={() => setEditing("category")}
          onCancel={() => setEditing(null)}
          onClear={tx.category_id ? () => { patch.mutate({ category_id: null }); setEditing(null); } : undefined}
          value={tx.category_id
            ? (
              <Link to={`/categories#id=${tx.category_id}`} className="hover:underline">
                {tx.category_parent_name && <span className="text-muted-foreground">{tx.category_parent_name} › </span>}
                {tx.category_name}
              </Link>
            )
            : null}
          editor={
            <CategoryCombobox
              value={tx.category_id ?? ""}
              onChange={(id) => {
                // Same "" while typing (and for the "No category" row) — clearing is the explicit button.
                if (!id) return;
                patch.mutate({ category_id: id });
                setEditing(null);
              }}
              categories={categories}
              placeholder="Search categories…"
              className="flex-1"
              autoFocus
              onClose={() => setEditing(null)}
            />
          }
        />
      </dl>
      <TransactionTags tx={tx} label={null} />
      <Textarea
        value={memo}
        onChange={(e) => setMemo(e.target.value)}
        onBlur={() => {
          const next = memo.trim() || null;
          if (next !== (tx.memo ?? null)) patch.mutate({ memo: next });
        }}
        onKeyDown={(e) => { if (e.key === "Escape") { setMemo(tx.memo ?? ""); e.currentTarget.blur(); } }}
        placeholder="Add a note — what was this?"
        aria-label="Note"
        rows={2}
        className="resize-none text-sm"
      />
    </Group>
  );
}

function EditRow({ label, value, editing, onEdit, onCancel, onClear, editor }: {
  label: string;
  value: React.ReactNode | null;
  editing: boolean;
  onEdit: () => void;
  onCancel: () => void;
  onClear?: () => void;
  editor: React.ReactNode;
}) {
  if (editing) {
    return (
      <div className="space-y-1">
        <dt className="text-muted-foreground">{label}</dt>
        <dd className="flex">{editor}</dd>
        <div className="flex items-center gap-1">
          <Button size="xs" variant="ghost" className="text-muted-foreground" onClick={onCancel}>Cancel</Button>
          {onClear && (
            <Button size="xs" variant="ghost" className="text-muted-foreground" onClick={onClear}>
              Clear {label.toLowerCase()}
            </Button>
          )}
        </div>
      </div>
    );
  }
  return (
    <div className="flex min-h-7 items-center justify-between gap-3">
      <dt className="shrink-0 text-muted-foreground">{label}</dt>
      <dd className="flex min-w-0 items-center gap-1.5">
        <span className="truncate text-right">{value ?? <span className="text-muted-foreground">—</span>}</span>
        <button
          onClick={onEdit}
          className="shrink-0 rounded p-0.5 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          aria-label={`Edit ${label.toLowerCase()}`}
          title={`Edit ${label.toLowerCase()}`}
        >
          <Pencil size={12} />
        </button>
      </dd>
    </div>
  );
}

// ── How it counts ─────────────────────────────────────────────────────────────

function Counting({ tx, ctx }: { tx: CashTransaction; ctx: TransactionContext | undefined }) {
  const { patch } = useTransactionMutations(tx.id);
  const spends = ctx?.treatment.spend ?? false;

  return (
    <Group title="How it counts">
      {ctx && (
        <div className="space-y-2 text-sm">
          <CountLine on={spends || ctx.treatment.income} label={spendReason(tx, ctx)}>
            {ctx.treatment.merchant_excluded && tx.merchant_id && (
              <Link to={`/merchants#id=${tx.merchant_id}`} className="text-xs text-primary hover:underline">Merchant settings</Link>
            )}
          </CountLine>
          {spends && (
            <CountLine on={!tx.budget_excluded} label={tx.budget_excluded ? "Left out of budgets" : "Counted in budgets"}>
              <Button
                size="xs"
                variant="ghost"
                className="text-muted-foreground"
                onClick={() => patch.mutate({ budget_excluded: !tx.budget_excluded })}
                disabled={patch.isPending}
                title={tx.budget_excluded ? undefined : "For one-off purchases: still counts in cashflow, but not against a budget"}
              >
                {tx.budget_excluded ? "Count it" : "Leave out"}
              </Button>
            </CountLine>
          )}
        </div>
      )}
      <div className="space-y-2">
        <TransferTools tx={tx} />
      </div>
    </Group>
  );
}

function CountLine({ on, label, children }: { on: boolean; label: string; children?: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2">
      <span aria-hidden className={cn("size-1.5 shrink-0 rounded-full", on ? "bg-positive" : "bg-muted-foreground/40")} />
      <span className="min-w-0 flex-1">{label}</span>
      {children}
    </div>
  );
}

// ── Automate ──────────────────────────────────────────────────────────────────

function Automate({ tx, ctx }: { tx: CashTransaction; ctx: TransactionContext | undefined }) {
  const [open, setOpen] = useState(false);
  const [tracking, setTracking] = useState(false);
  // A charge already on a live subscription is managed from its section.
  const tracked = !!ctx?.series && ["active", "suggested", "lapsed"].includes(ctx.series.status);
  const pattern = normalizeDescription(tx.description) || tx.description;
  const others = ctx ? Math.max(ctx.history.total - 1, 0) : 0;

  return (
    <Group title="Automate">
      <p className="text-sm text-muted-foreground">
        {pattern
          ? <>Set the merchant, category or tags for every future <span className="font-medium text-foreground">{pattern}</span> charge{others > 0 && <> — and apply it to the {others} already here</>}.</>
          : "Set the merchant, category or tags for charges like this as they arrive."}
      </p>
      <Button size="sm" variant="outline" onClick={() => setOpen(true)} className="w-full">
        <Zap size={14} />
        Create automation
      </Button>
      {ctx && !tracked && canTrackAsSubscription(tx) && (
        <Button size="sm" variant="ghost" onClick={() => setTracking(true)} className="w-full text-muted-foreground">
          <Repeat size={14} />
          Track as subscription
        </Button>
      )}
      {open && <QuickAutomationModal tx={tx} onClose={() => setOpen(false)} />}
      {tracking && ctx && (
        <TrackSubscriptionDialog tx={tx} ctx={ctx} presetCadence={roughRhythm(ctx)?.cadenceKey} onClose={() => setTracking(false)} />
      )}
    </Group>
  );
}

// ── Record ────────────────────────────────────────────────────────────────────

function Record({ tx }: { tx: CashTransaction }) {
  const navigate = useNavigate();
  const confirm = useConfirm();
  const { destroy } = useTransactionMutations(tx.id);
  const { data, isLoading, isError } = useQuery(queries.activity({ subjectType: "CashTransaction", subjectId: tx.id }));
  const entries = data?.entries ?? [];

  async function remove() {
    const ok = await confirm({
      title: "Delete this transaction?",
      description: "It's removed from every total. If it came from an import or a bank sync, re-running it may bring it back.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    destroy.mutate(undefined, { onSuccess: () => { toast.success("Transaction deleted"); navigate("/transactions", { replace: true }); } });
  }

  return (
    <Group title="Record">
      <dl className="space-y-1.5 text-xs">
        <Meta label="Imported as" value={`${tx.transaction_type ?? "—"} · ${tx.source.replace("_", " ")}`} />
        {tx.post_date && tx.post_date !== tx.transaction_date && <Meta label="Posted" value={formatDate(tx.post_date)} />}
        {tx.balance != null && <Meta label="Balance after" value={formatCurrency(tx.balance)} />}
        {tx.loan_id && <Meta label="Loan" value={<Link to={`/loans/${tx.loan_id}`} className="hover:underline">{tx.loan_name}</Link>} />}
        <Meta label="Added" value={formatDate(tx.created_at)} />
        <Meta label="ID" value={<code className="font-mono text-tiny">{tx.id.slice(0, 8)}</code>} />
      </dl>

      <div className="space-y-2">
        <p className="text-xs font-medium text-muted-foreground">Activity</p>
        {isLoading && <Skeleton className="h-10 rounded-lg" />}
        {isError && (
          <p className="flex items-center gap-1.5 text-xs text-negative"><AlertTriangle size={12} /> Couldn't load activity.</p>
        )}
        {!isLoading && !isError && entries.length === 0 && (
          <p className="text-xs text-muted-foreground">No activity recorded for this transaction.</p>
        )}
        {entries.length > 0 && <div className="space-y-2">{entries.map((e) => <ActivityRow key={e.id} entry={e} />)}</div>}
      </div>

      <Button size="xs" variant="ghost" className="-ml-2 text-destructive" onClick={remove} disabled={destroy.isPending}>
        <Trash2 size={12} />
        Delete transaction
      </Button>
    </Group>
  );
}

function Meta({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="truncate text-right">{value}</dd>
    </div>
  );
}
