import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowRight, ArrowLeftRight, ArrowUpRight, Check, RefreshCw, X } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon } from "@/components/StatRibbon";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs } from "@/components/ui/tabs";
import { toast } from "@/components/ui/toast";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import { runBatch } from "@/lib/batch";
import { monthLabel } from "@/lib/monthLabel";
import type { Account, TransferCandidate } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Transfers ─────────────────────────────────────────────────────────────────
// Money movement between accounts — excluded from spending & income. The page
// serves three jobs, in priority order:
//   1. Triage: detected transfer pairs waiting for review (confirm/dismiss).
//   2. Audit: a month-grouped ledger of everything currently excluded,
//      including one-sided transfers to external/untracked accounts, with
//      unlink as the undo.
//   3. Patterns: where money regularly moves (stat ribbon: volume, top flow).
// Rows come from GET /transfers (most recent 200) — totals are computed
// client-side over that window.

type Scope = "all" | "internal" | "external" | "card_payments" | "loan_payments";

export function TransfersSection() {
  const qc = useQueryClient();
  const confirmDialog = useConfirm();

  const { data: transfers = [], isLoading: txLoading } = useQuery(queries.transfers());
  const { data: candidates = [], isLoading: candLoading, refetch: refetchCandidates } = useQuery(queries.transferCandidates());
  const { data: accounts = [] } = useQuery(queries.accounts());

  const accountById = useMemo(() => new Map(accounts.map((a) => [a.id, a])), [accounts]);

  const [scope, setScope] = useState<Scope>("all");
  const [accountFilter, setAccountFilter] = useState("");
  const [search, setSearch] = useState("");

  // ── Mutations ──────────────────────────────────────────────────────────────

  const confirm = useMutation({
    mutationFn: (id: string) => api.post(`/transfers/${id}/confirm`, {}),
    onSuccess: () => {
      invalidate(qc, keys.transfers, keys.cashTransactions);
      toast.success("Transfer confirmed");
    },
  });

  const confirmAll = useMutation({
    mutationFn: async (ids: string[]) => {
      // Worker pool instead of a serial await-per-id loop: each confirm
      // bumps the server's cache version, so serial round-trips also made
      // every interleaved read a cache miss.
      const { succeeded, failed } = await runBatch(ids, (id) => api.post(`/transfers/${id}/confirm`, {}));
      return { confirmed: succeeded.length, failed: failed.length };
    },
    onSuccess: ({ confirmed, failed }) => {
      invalidate(qc, keys.transfers, keys.cashTransactions);
      if (failed > 0) toast.error(`Confirmed ${confirmed} transfers, ${failed} failed`);
      else toast.success(`Confirmed ${confirmed} transfers`);
    },
  });

  const dismiss = useMutation({
    // Not DELETE: dismissal records the rejected pair server-side so
    // detection never re-suggests it.
    mutationFn: (id: string) => api.post(`/transfers/${id}/dismiss`, {}),
    onSuccess: () => invalidate(qc, keys.transfers),
  });

  const unlink = useMutation({
    mutationFn: (id: string) => api.delete(`/transfers/${id}`),
    onSuccess: () => {
      invalidate(qc, keys.transfers, keys.cashTransactions);
      toast.success("Transfer unlinked");
    },
  });

  const scan = useMutation({
    mutationFn: () => api.post("/transfers/scan", {}),
    onSuccess: () => {
      toast.info("Scanning for transfers…");
      setTimeout(() => refetchCandidates(), 2000);
    },
  });

  async function handleUnlink(t: TransferCandidate) {
    const ok = await confirmDialog({
      title: "Unlink this transfer?",
      description: "The transactions will count toward spending and income again.",
      confirmLabel: "Unlink",
      destructive: true,
    });
    if (ok) unlink.mutate(t.id);
  }

  // ── Derived data ───────────────────────────────────────────────────────────

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    return transfers
      .map((t) => decorate(t, accountById))
      .filter((r) =>
        scope === "all" ? true
        : scope === "card_payments" ? r.transfer.kind === "credit_card_payment"
        : scope === "loan_payments" ? r.transfer.kind === "loan_payment"
        : r.scope === scope)
      .filter((r) => !accountFilter || r.accountIds.includes(accountFilter))
      .filter((r) =>
        !q ||
        r.searchText.includes(q))
      .sort((a, b) => (b.date ?? "").localeCompare(a.date ?? ""));
  }, [transfers, accountById, scope, accountFilter, search]);

  const months = useMemo(() => {
    const groups = new Map<string, DecoratedTransfer[]>();
    for (const r of rows) {
      const key = r.date?.slice(0, 7) ?? "unknown";
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key)!.push(r);
    }
    return [...groups.entries()];
  }, [rows]);

  const stats = useMemo(() => buildStats(transfers, accountById), [transfers, accountById]);

  const filtered = scope !== "all" || !!accountFilter || search.trim() !== "";

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <div className="flex flex-col">
      <PageHeader
        title="Transfers"
        sticky
        actions={[ {
          label: scan.isPending ? "Scanning…" : "Scan for transfers",
          icon: RefreshCw,
          onSelect: () => scan.mutate(),
          disabled: scan.isPending,
        } ]}
      />

      <StatRibbon borderTop={false} stats={[
        { label: "Moved this month", value: formatCurrency(stats.thisMonth) },
        { label: "Last month",       value: formatCurrency(stats.lastMonth) },
        { label: "Top flow · 90d",   value: stats.topFlow ?? "—", dividerBefore: true },
        { label: "To external · 90d", value: formatCurrency(stats.external90) },
        { label: "Paid to cards · this mo", value: formatCurrency(stats.cardPaymentsThisMonth) },
      ]} />

      <div className="space-y-6 p-6">
        {/* 1 — Review queue */}
        {(candLoading || candidates.length > 0) && (
          <section className="overflow-hidden rounded-xl border">
            <div className="flex items-center justify-between gap-2 border-b bg-muted/30 px-4 py-2.5">
              <div>
                <h2 className="text-sm font-semibold">Needs review{candidates.length > 0 && ` (${candidates.length})`}</h2>
                <p className="text-xs text-muted-foreground">Detected matches — confirm to exclude from spending &amp; income</p>
              </div>
              {candidates.length > 1 && (
                <Button
                  variant="outline"
                  size="xs"
                  onClick={() => confirmAll.mutate(candidates.map((c) => c.id))}
                  disabled={confirmAll.isPending}
                >
                  {confirmAll.isPending ? "Confirming…" : `Confirm all ${candidates.length}`}
                </Button>
              )}
            </div>
            {candLoading ? (
              <div className="space-y-1 p-3">
                {[1, 2].map((i) => <Skeleton key={i} className="h-12 rounded-lg" />)}
              </div>
            ) : (
              <div className="divide-y">
                {candidates.map((c) => (
                  <CandidateRow
                    key={c.id}
                    candidate={c}
                    accountById={accountById}
                    busy={confirm.isPending || confirmAll.isPending}
                    onConfirm={() => confirm.mutate(c.id)}
                    onDismiss={() => dismiss.mutate(c.id)}
                  />
                ))}
              </div>
            )}
          </section>
        )}

        {/* 2 — Ledger */}
        <section className="space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <Tabs<Scope>
              aria-label="Transfer scope"
              size="sm"
              value={scope}
              onChange={setScope}
              options={[
                { value: "all", label: "All" },
                { value: "internal", label: "Internal" },
                { value: "external", label: "External" },
                { value: "card_payments", label: "Card payments" },
                { value: "loan_payments", label: "Loan payments" },
              ]}
            />
            <div className="ml-auto flex items-center gap-2">
              <Select
                aria-label="Filter by account"
                value={accountFilter}
                onChange={(e) => setAccountFilter(e.target.value)}
                className="h-8 text-xs"
                wrapperClassName="w-44"
              >
                <option value="">All accounts</option>
                {accounts.filter((a) => !a.hidden).map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}{a.kind === "external" ? " (external)" : ""}
                  </option>
                ))}
              </Select>
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search transfers…"
                aria-label="Search transfers"
                className="h-8 w-52 text-xs"
              />
            </div>
          </div>

          {txLoading ? (
            <div className="space-y-1">
              {[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-14 rounded-xl" />)}
            </div>
          ) : rows.length === 0 ? (
            <div className="rounded-xl border">
              {filtered ? (
                <EmptyState title="No transfers match the current filters." />
              ) : (
                <EmptyState
                  icon={ArrowLeftRight}
                  title="No transfers yet."
                  description='Confirm suggestions here, or open any transaction and choose "Link as transfer" — including to accounts outside Fin.'
                  action={
                    <Button variant="outline" size="sm" onClick={() => scan.mutate()} disabled={scan.isPending}>
                      {scan.isPending ? "Scanning…" : "Scan for transfers"}
                    </Button>
                  }
                />
              )}
            </div>
          ) : (
            <div className="overflow-hidden rounded-xl border">
              {months.map(([month, group]) => (
                <div key={month}>
                  <div className="flex items-baseline justify-between border-b bg-muted/30 px-4 py-1.5">
                    <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      {month === "unknown" ? "Undated" : monthLabel(month)}
                    </h3>
                    <p className="text-xs tabular-nums text-muted-foreground">
                      {group.length} {group.length === 1 ? "transfer" : "transfers"} · {formatCurrency(sum(group))}
                    </p>
                  </div>
                  <div className="divide-y">
                    {group.map((r) => (
                      <LedgerRow key={r.transfer.id} row={r} onUnlink={() => handleUnlink(r.transfer)} />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>
    </div>
  );
}

// ── Row decoration ────────────────────────────────────────────────────────────

interface Side {
  name: string;
  /** True when this side has no tracked transaction (counterparty account). */
  counterparty: boolean;
  external: boolean;
}

interface DecoratedTransfer {
  transfer: TransferCandidate;
  date: string | null;
  from: Side;
  to: Side;
  description: string | null;
  scope: Exclude<Scope, "all">;
  accountIds: string[];
  searchText: string;
  /** Cash transaction to open from the row, when one exists. */
  txnLink: string | null;
}

function side(t: TransferCandidate, which: "from" | "to", accountById: Map<string, Account>): Side {
  const accountId = which === "from" ? t.from_account_id : t.to_account_id;
  const hasTxn = which === "from" ? !!t.from_transaction_id : !!t.to_transaction_id;
  if (hasTxn) {
    return { name: accountId ? accountById.get(accountId)?.name ?? "—" : "—", counterparty: false, external: false };
  }
  const cp = t.counterparty_account_id ? accountById.get(t.counterparty_account_id) : null;
  return {
    name: t.counterparty_account_name ?? cp?.name ?? "—",
    counterparty: true,
    external: cp?.kind === "external",
  };
}

function isExternal(t: TransferCandidate, accountById: Map<string, Account>): boolean {
  return !!t.counterparty_account_id && accountById.get(t.counterparty_account_id)?.kind === "external";
}

function decorate(t: TransferCandidate, accountById: Map<string, Account>): DecoratedTransfer {
  const from = side(t, "from", accountById);
  const to = side(t, "to", accountById);
  const description = t.from_description ?? t.to_description ?? null;
  const accountIds = [t.from_account_id, t.to_account_id, t.counterparty_account_id].filter(Boolean) as string[];
  const txnId =
    t.from_transaction_id && t.from_transaction_type === "CashTransaction" ? t.from_transaction_id
    : t.to_transaction_id && t.to_transaction_type === "CashTransaction" ? t.to_transaction_id
    : null;
  return {
    transfer: t,
    date: t.from_date ?? t.to_date ?? t.created_at?.slice(0, 10) ?? null,
    from,
    to,
    description,
    scope: isExternal(t, accountById) ? "external" : "internal",
    accountIds,
    searchText: [from.name, to.name, description ?? ""].join(" ").toLowerCase(),
    txnLink: txnId,
  };
}

function sum(group: DecoratedTransfer[]): number {
  return group.reduce((acc, r) => acc + (r.transfer.amount ?? 0), 0);
}

// ── Stats ─────────────────────────────────────────────────────────────────────

function buildStats(transfers: TransferCandidate[], accountById: Map<string, Account>) {
  const now = new Date();
  const thisMonthKey = now.toISOString().slice(0, 7);
  const lastMonthKey = new Date(now.getFullYear(), now.getMonth() - 1, 15).toISOString().slice(0, 7);
  const cutoff90 = new Date(now.getTime() - 90 * 24 * 3600 * 1000).toISOString().slice(0, 10);

  let thisMonth = 0;
  let lastMonth = 0;
  let external90 = 0;
  let cardPaymentsThisMonth = 0;
  const flows = new Map<string, number>();

  for (const t of transfers) {
    const date = t.from_date ?? t.to_date ?? t.created_at?.slice(0, 10);
    const amount = t.amount ?? 0;
    if (!date) continue;
    if (date.slice(0, 7) === thisMonthKey) thisMonth += amount;
    if (date.slice(0, 7) === thisMonthKey && t.kind === "credit_card_payment") cardPaymentsThisMonth += amount;
    if (date.slice(0, 7) === lastMonthKey) lastMonth += amount;
    if (date >= cutoff90) {
      if (isExternal(t, accountById)) external90 += amount;
      const from = side(t, "from", accountById).name;
      const to = side(t, "to", accountById).name;
      if (from !== "—" && to !== "—") {
        flows.set(`${from} → ${to}`, (flows.get(`${from} → ${to}`) ?? 0) + amount);
      }
    }
  }

  const topFlow = [...flows.entries()].sort((a, b) => b[1] - a[1])[0];
  return {
    thisMonth,
    lastMonth,
    external90,
    cardPaymentsThisMonth,
    topFlow: topFlow ? `${topFlow[0]} · ${formatCurrency(topFlow[1], true)}` : null,
  };
}

// ── Rows ──────────────────────────────────────────────────────────────────────

function SideLabel({ s }: { s: Side }) {
  return (
    <span className="inline-flex min-w-0 items-center gap-1.5">
      <span className="truncate">{s.name}</span>
      {s.external && <Badge variant="outline" className="shrink-0">External</Badge>}
    </span>
  );
}

function CandidateRow({ candidate: c, accountById, busy, onConfirm, onDismiss }: {
  candidate: TransferCandidate;
  accountById: Map<string, Account>;
  busy: boolean;
  onConfirm: () => void;
  onDismiss: () => void;
}) {
  const fromName = c.from_account_id ? accountById.get(c.from_account_id)?.name ?? "—" : "—";
  const toName = c.to_account_id ? accountById.get(c.to_account_id)?.name ?? "—" : "—";
  return (
    <div className="flex items-center gap-3 px-4 py-2.5">
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5 text-sm">
          <span className="truncate font-medium">{fromName}</span>
          <ArrowRight size={12} className="shrink-0 text-muted-foreground" />
          <span className="truncate font-medium">{toName}</span>
          <span className="ml-1 shrink-0 tabular-nums">{c.amount != null ? formatCurrency(c.amount) : "—"}</span>
          <KindBadge t={c} />
        </div>
        <p className="truncate text-xs text-muted-foreground">
          {c.from_description ?? c.to_description ?? "—"}
          {c.from_date && <> · {formatDate(c.from_date)}</>}
          {c.date_diff != null && c.date_diff > 0 && <> · {c.date_diff}d apart</>}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-1">
        <Button size="xs" onClick={onConfirm} disabled={busy} className="gap-1">
          <Check size={11} />
          Confirm
        </Button>
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={onDismiss}
          disabled={busy}
          className="text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
          title="Dismiss"
          aria-label="Dismiss candidate"
        >
          <X size={13} />
        </Button>
      </div>
    </div>
  );
}

function KindBadge({ t }: { t: TransferCandidate }) {
  if (t.kind === "transfer") return null;
  return (
    <Badge variant="outline" className="shrink-0">
      {t.kind === "credit_card_payment" ? "Card payment" : "Loan payment"}
      {t.confirmation_source === "auto" && " · auto"}
    </Badge>
  );
}

function LedgerRow({ row: r, onUnlink }: { row: DecoratedTransfer; onUnlink: () => void }) {
  const navigate = useNavigate();
  return (
    <div className="group flex items-center gap-3 px-4 py-2.5">
      <span className="w-20 shrink-0 text-xs text-muted-foreground">
        {r.date ? formatDate(r.date) : "—"}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5 text-sm">
          <SideLabel s={r.from} />
          <ArrowRight size={12} className="shrink-0 text-muted-foreground" />
          <SideLabel s={r.to} />
          <KindBadge t={r.transfer} />
          {r.transfer.include_in_spend && (
            <Badge variant="outline" className="shrink-0">Counted as spend</Badge>
          )}
        </div>
        {r.description && (
          <p className="truncate text-xs text-muted-foreground">{r.description}</p>
        )}
      </div>
      <span className="shrink-0 text-sm font-medium tabular-nums">
        {r.transfer.amount != null ? formatCurrency(r.transfer.amount) : "—"}
      </span>
      <div className="flex shrink-0 items-center gap-0.5">
        {r.txnLink && (
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => navigate(`/transactions/${r.txnLink}`)}
            className={cn("text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 focus-visible:opacity-100")}
            title="Open transaction"
            aria-label="Open transaction"
          >
            <ArrowUpRight size={13} />
          </Button>
        )}
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={onUnlink}
          className="text-muted-foreground opacity-0 transition-opacity hover:bg-destructive/10 hover:text-destructive group-hover:opacity-100 focus-visible:opacity-100"
          title="Unlink transfer"
          aria-label="Unlink transfer"
        >
          <X size={13} />
        </Button>
      </div>
    </div>
  );
}
