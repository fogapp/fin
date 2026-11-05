import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Download, Pencil, Plus, Trash2, TriangleAlert } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/toast";
import { cn, formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import { TaxProfileForm } from "./equity/TaxProfileForm";
import { KindBadge } from "./taxes/KindBadge";
import { PaymentDialog } from "./taxes/PaymentDialog";
import { AdjustmentDialog } from "./taxes/AdjustmentDialog";
import type { TaxAdjustment, TaxChecklistItem, TaxReport, TaxSafeHarbor } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Taxes ─────────────────────────────────────────────────────────────────────
// The tax year as a first-class object. Every section declares its nature:
// FACT (computed from the ledger), RECORD (user bookkeeping), or ESTIMATE
// (model output, always with assumptions). Estimates never look like filing
// numbers.

const CURRENT_YEAR = new Date().getFullYear();

const DOC_KIND_LABELS: Record<string, string> = {
  w2: "W-2",
  "1099_consolidated": "Consolidated 1099",
  "1099_int": "1099-INT",
  "1099_r": "1099-R",
  k1: "K-1",
  "1098": "1098 (mortgage)",
  "3921": "3921 (ISO exercise)",
  "3922": "3922 (ESPP)",
  "5498": "5498 (IRA)",
  property_tax: "Property tax",
  charitable_receipt: "Charitable receipt",
  other: "Other",
};

export function Taxes() {
  const qc = useQueryClient();
  const [year, setYear] = useState(CURRENT_YEAR);
  const [editingProfile, setEditingProfile] = useState(false);
  const [paymentDialog, setPaymentDialog] = useState(false);
  const [adjustmentDialog, setAdjustmentDialog] = useState<{ adjustment?: TaxAdjustment } | null>(null);

  const { data: report, isPending, isError, refetch } = useQuery(queries.taxReport(year));
  const profileComplete = report?.profile?.complete ?? false;
  // The report's profile is null until one is saved — the editable default
  // comes from the tax_profile endpoint.
  const { data: profileDefault } = useQuery({
    ...queries.taxProfile(year),
    enabled: !!report && (!profileComplete || editingProfile),
  });

  async function exportYear() {
    try {
      const bundle = await api.get<unknown>(`/tax/export?year=${year}`);
      const blob = new Blob([JSON.stringify(bundle, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `fin-tax-${year}.json`;
      a.click();
      URL.revokeObjectURL(url);
      toast.success(`Exported ${year} tax bundle`);
    } catch (e) {
      toast.error((e as Error).message);
    }
  }

  const profileForForm = report?.profile ?? profileDefault ?? null;

  return (
    <div className="flex flex-col">
      <PageHeader
        title="Taxes"
        level={1}
        sticky
        actions={[ { label: "Export year", icon: Download, onSelect: exportYear } ]}
      >
        <div className="flex items-center gap-1">
          <Button variant="ghost" size="icon-sm" aria-label="Previous year" onClick={() => setYear((y) => y - 1)}>
            <ChevronLeft size={14} />
          </Button>
          <span className="w-12 text-center text-sm font-semibold tabular-nums">{year}</span>
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label="Next year"
            onClick={() => setYear((y) => y + 1)}
            disabled={year >= CURRENT_YEAR + 1}
          >
            <ChevronRight size={14} />
          </Button>
        </div>
      </PageHeader>

      <div className="space-y-6 p-6">
        {isPending ? (
          <>
            <Skeleton className="h-28 rounded-xl" />
            <div className="grid gap-6 xl:grid-cols-2">
              <Skeleton className="h-64 rounded-xl" />
              <Skeleton className="h-64 rounded-xl" />
            </div>
          </>
        ) : isError || !report ? (
          <ErrorState title={`Failed to load the ${year} tax report`} onRetry={() => refetch()} />
        ) : (
          <>
            {/* Profile prompt / editor */}
            {(!profileComplete || editingProfile) ? (
              profileForForm && (
                <section className="rounded-xl border bg-muted/30 p-4">
                  {!profileComplete && (
                    <p className="mb-3 text-sm text-muted-foreground">
                      Enter the {year} tax profile to unlock the liability estimate — the facts below work either way.
                    </p>
                  )}
                  <TaxProfileForm
                    profile={profileForForm}
                    onSaved={() => { setEditingProfile(false); invalidate(qc, keys.taxReport); }}
                    onCancel={profileComplete ? () => setEditingProfile(false) : undefined}
                  />
                </section>
              )
            ) : (
              report.profile && (
                <button
                  onClick={() => setEditingProfile(true)}
                  className="flex w-full items-center gap-2 rounded-lg border bg-muted/30 px-3 py-2 text-left text-xs text-muted-foreground transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  <span className="font-medium text-foreground">{year} tax profile</span>
                  {report.profile.filing_status === "mfj" ? "Married filing jointly" : "Single"} · {report.profile.state} ·
                  wages {formatCurrency(report.profile.projected_wages, true)}
                  <Pencil size={12} className="ml-auto shrink-0" />
                </button>
              )
            )}

            {/* Hero — liability estimate */}
            {report.liability && <LiabilityHero report={report} />}

            <div className="grid items-start gap-6 xl:grid-cols-2">
              <IncomeCard report={report} />
              <DeductionsCard report={report} />
              <PaymentsCard report={report} onAddPayment={() => setPaymentDialog(true)} />
              <ContributionsCard report={report} />
              <DocumentsCard report={report} year={year} />
              <div className="space-y-6">
                {report.flags.wash_sales.length > 0 && <WashSalesCard report={report} />}
                <AdjustmentsCard
                  report={report}
                  onAdd={() => setAdjustmentDialog({})}
                  onEdit={(adjustment) => setAdjustmentDialog({ adjustment })}
                />
              </div>
            </div>

            <div className="space-y-1 border-t pt-3 text-xs text-muted-foreground">
              {report.liability && (
                <>
                  <p>
                    Tax tables: federal {year} ({report.liability.assumptions.figures_status.federal})
                    {report.liability.assumptions.figures_status.state && (
                      <> · California ({report.liability.assumptions.figures_status.state}
                      {report.liability.assumptions.figures_status.state === "projected" && " — FTB publishes final figures in the fall"})</>
                    )}.
                  </p>
                  <p>Assumptions: {report.liability.assumptions.notes.join("; ")}.</p>
                </>
              )}
              <p className="font-medium">
                Estimates are scenarios under the stated assumptions — not tax advice and not filing numbers.
                Confirm everything with a professional.
              </p>
            </div>
          </>
        )}
      </div>

      {paymentDialog && <PaymentDialog taxYear={year} stateName={report?.profile?.state_name} onClose={() => setPaymentDialog(false)} />}
      {adjustmentDialog && (
        <AdjustmentDialog taxYear={year} adjustment={adjustmentDialog.adjustment} onClose={() => setAdjustmentDialog(null)} />
      )}
    </div>
  );
}

// ── Sections ──────────────────────────────────────────────────────────────────

function SectionCard({ title, kind, action, children }: {
  title: string;
  kind?: "fact" | "record" | "estimate";
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="overflow-hidden rounded-xl border">
      <div className="flex items-center gap-2 border-b bg-muted/30 px-4 py-2.5">
        <h2 className="text-sm font-semibold">{title}</h2>
        {kind && <KindBadge kind={kind} />}
        <div className="ml-auto">{action}</div>
      </div>
      <div className="p-4">{children}</div>
    </section>
  );
}

function Row({ label, value, sub, valueClass }: { label: React.ReactNode; value: React.ReactNode; sub?: string; valueClass?: string }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-1 text-sm">
      <span className="min-w-0">
        {label}
        {sub && <span className="block text-xs text-muted-foreground">{sub}</span>}
      </span>
      <span className={cn("shrink-0 tabular-nums", valueClass)}>{value}</span>
    </div>
  );
}

function LiabilityHero({ report }: { report: TaxReport }) {
  const l = report.liability!;
  const st = report.profile?.state ?? "State";
  const combined = l.federal.projected_refund_or_owed + l.state.projected_refund_or_owed;
  const withheld = l.federal.withheld_and_paid + l.state.withheld_and_paid;
  return (
    <section className="rounded-xl border bg-primary/5 p-4">
      <div className="flex flex-wrap items-center gap-x-8 gap-y-3">
        <div>
          <p className="text-xs text-muted-foreground">Projected liability <KindBadge kind="estimate" /></p>
          <p className="text-xl font-semibold tabular-nums">{formatCurrency(l.total_liability)}</p>
          <p className="text-xs text-muted-foreground">
            federal {formatCurrency(l.federal.total)}{l.federal.amt > 0 && <> (incl. {formatCurrency(l.federal.amt)} AMT)</>} ·
            {st} {formatCurrency(l.state.total)}{l.state.amt > 0 && <> (incl. {formatCurrency(l.state.amt)} AMT)</>}
          </p>
        </div>
        <div>
          <p className="text-xs text-muted-foreground">Withheld + paid</p>
          <p className="text-xl font-semibold tabular-nums">{formatCurrency(withheld)}</p>
        </div>
        <div>
          <p className="text-xs text-muted-foreground">{combined >= 0 ? "Projected refund" : "Projected amount owed"}</p>
          <p className={cn("text-2xl font-semibold tabular-nums", moneyColor(combined))}>
            {formatCurrency(Math.abs(combined))}
          </p>
          <p className="text-xs text-muted-foreground">
            federal {formatCurrency(l.federal.projected_refund_or_owed)} · {st} {formatCurrency(l.state.projected_refund_or_owed)}
          </p>
        </div>
        <div className="text-xs text-muted-foreground">
          <p>
            Effective {(l.federal.effective_rate * 100).toFixed(1)}% fed · {(l.state.effective_rate * 100).toFixed(1)}% {st} ·
            marginal {l.federal.marginal_ordinary_rate != null ? `${(l.federal.marginal_ordinary_rate * 100).toFixed(0)}%` : "—"}
            {l.state.marginal_ordinary_rate != null && <> / {(l.state.marginal_ordinary_rate * 100).toFixed(1)}%</>}
          </p>
          {l.bracket_headroom.to_next_federal_bracket && (
            <p>
              {formatCurrency(l.bracket_headroom.to_next_federal_bracket.amount, true)} of room before the{" "}
              {(l.bracket_headroom.to_next_federal_bracket.next_rate * 100).toFixed(0)}% bracket
            </p>
          )}
          {l.bracket_headroom.ltcg_zero_headroom > 0 && (
            <p>{formatCurrency(l.bracket_headroom.ltcg_zero_headroom, true)} of 0% LTCG headroom</p>
          )}
        </div>
      </div>
    </section>
  );
}

function IncomeCard({ report }: { report: TaxReport }) {
  const inc = report.income;
  const eq = inc.equity_comp;
  return (
    <SectionCard title="Income" kind="fact">
      <Row label="Wages (projected)" value={formatCurrency(inc.wages.amount)} />
      <Row label="Interest" value={formatCurrency(inc.interest)} />
      <Row label="Dividends" value={formatCurrency(inc.dividends)} />
      <Row
        label="Realized gains — short term"
        value={formatCurrency(inc.realized_gains.short_term)}
        valueClass={moneyColor(inc.realized_gains.short_term)}
      />
      <Row
        label="Realized gains — long term"
        value={formatCurrency(inc.realized_gains.long_term)}
        valueClass={moneyColor(inc.realized_gains.long_term)}
      />
      {inc.realized_gains.by_security.length > 0 && (
        <div className="mt-1 max-h-36 overflow-y-auto rounded-lg border text-xs">
          {inc.realized_gains.by_security.map((s) => (
            <div key={s.security_id} className="flex justify-between gap-2 border-b px-2.5 py-1 last:border-0">
              <span className="truncate">{s.label}</span>
              <span className={cn("tabular-nums", moneyColor(s.total))}>{formatCurrency(s.total)}</span>
            </div>
          ))}
        </div>
      )}
      {(eq.ordinary_income > 0 || eq.iso_amt_spread > 0) && (
        <div className="mt-2 rounded-lg border bg-muted/20 p-2.5">
          <p className="mb-1 text-xs font-medium text-muted-foreground">
            Equity compensation · <a href="/investments#section=equity" className="text-primary hover:underline">plan exercises →</a>
          </p>
          {eq.ordinary_income > 0 && (
            <Row label="Ordinary income (NSO exercises, RSU settlements)" value={formatCurrency(eq.ordinary_income)} />
          )}
          {eq.iso_amt_spread > 0 && (
            <Row label="ISO spread (AMT only — not ordinary income)" value={formatCurrency(eq.iso_amt_spread)} />
          )}
          {eq.notes.map((n, i) => (
            <p key={i} className="text-xs text-muted-foreground">{n}</p>
          ))}
        </div>
      )}
      {inc.adjustments.items.map((a) => (
        <Row key={a.id} label={`${a.label} (adjustment)`} value={formatCurrency(a.amount)} />
      ))}
    </SectionCard>
  );
}

function DeductionsCard({ report }: { report: TaxReport }) {
  const d = report.deductions;
  const qc = useQueryClient();
  const toggleReceipt = useMutation({
    mutationFn: ({ id, received }: { id: string; received: boolean }) =>
      api.patch(`/tax/checklist_items/${id}`, { status: received ? "received" : "expected" }),
    onSuccess: () => invalidate(qc, keys.taxReport),
  });

  // Receipt checkboxes patch the auto-seeded charitable_receipt checklist item
  // linked to the gift's transaction.
  const receiptItemFor = (transactionId: string) =>
    report.documents.items.find((i) => i.kind === "charitable_receipt" && i.reference_id === transactionId);

  return (
    <SectionCard title="Deductions" kind="fact">
      <Row label="Mortgage interest" value={formatCurrency(d.mortgage_interest.total)} />
      {d.mortgage_interest.loans.map((l) => (
        <Row
          key={l.loan_id}
          label={<span className="pl-3 text-xs text-muted-foreground">{l.name}</span>}
          value={<span className="text-xs">{formatCurrency(l.interest_paid)}</span>}
        />
      ))}
      <Row label="State & local taxes paid" sub="State withholding + estimated payments" value={formatCurrency(d.salt.amount)} />
      <Row label="Charitable gifts" value={formatCurrency(d.charitable.total)} />
      {d.charitable.gifts.length > 0 && (
        <div className="mt-1 max-h-36 overflow-y-auto rounded-lg border text-xs">
          {d.charitable.gifts.map((g) => {
            const item = receiptItemFor(g.transaction_id);
            return (
              <div key={g.transaction_id} className="flex items-center justify-between gap-2 border-b px-2.5 py-1 last:border-0">
                <span className="min-w-0 truncate">{formatDate(g.date)} · {g.description}</span>
                <span className="flex shrink-0 items-center gap-2 tabular-nums">
                  {formatCurrency(g.amount)}
                  {item && (
                    <label className="flex cursor-pointer items-center gap-1 text-muted-foreground">
                      <input
                        type="checkbox"
                        checked={g.receipt}
                        onChange={(e) => toggleReceipt.mutate({ id: item.id, received: e.target.checked })}
                        className="h-3 w-3 accent-primary"
                        aria-label={`Receipt on file for ${g.description}`}
                      />
                      receipt
                    </label>
                  )}
                </span>
              </div>
            );
          })}
        </div>
      )}
      {d.adjustments.items.map((a) => (
        <Row key={a.id} label={`${a.label} (adjustment)`} value={formatCurrency(a.amount)} />
      ))}
    </SectionCard>
  );
}

function PaymentsCard({ report, onAddPayment }: { report: TaxReport; onAddPayment: () => void }) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const p = report.payments;
  const st = report.profile?.state ?? "State";

  const deletePayment = useMutation({
    mutationFn: (id: string) => api.delete(`/tax/estimated_payments/${id}`),
    onSuccess: () => {
      invalidate(qc, keys.taxReport);
      toast.success("Payment removed");
    },
  });

  async function handleDelete(id: string) {
    if (await confirm({ title: "Remove this payment record?", confirmLabel: "Remove", destructive: true })) {
      deletePayment.mutate(id);
    }
  }

  const allPayments = [...p.federal.estimated, ...p.state.estimated].sort((a, b) => a.paid_on.localeCompare(b.paid_on));

  return (
    <SectionCard
      title="Payments & safe harbor"
      kind="record"
      action={
        <Button variant="ghost" size="xs" onClick={onAddPayment} className="gap-1">
          <Plus size={12} />
          Record payment
        </Button>
      }
    >
      <Row label="Federal withholding (projected)" value={formatCurrency(p.federal.withholding)} />
      <Row label={`${st} withholding (projected)`} value={formatCurrency(p.state.withholding)} />
      {allPayments.length > 0 && (
        <div className="mt-1 divide-y rounded-lg border text-xs">
          {allPayments.map((pay) => (
            <div key={pay.id} className="group flex items-center justify-between gap-2 px-2.5 py-1">
              <span>
                {formatDate(pay.paid_on)} · {pay.jurisdiction === "federal" ? "IRS" : st}
                {pay.quarter && <span className="text-muted-foreground"> · {pay.quarter}</span>}
              </span>
              <span className="flex items-center gap-1 tabular-nums">
                {formatCurrency(pay.amount)}
                <Button
                  variant="ghost"
                  size="icon-sm"
                  aria-label="Remove payment"
                  onClick={() => handleDelete(pay.id)}
                  className="opacity-0 hover:bg-destructive/10 hover:text-destructive focus-visible:opacity-100 group-hover:opacity-100"
                >
                  <Trash2 size={11} />
                </Button>
              </span>
            </div>
          ))}
        </div>
      )}

      <div className="mt-3 space-y-1 text-sm">
        <SafeHarborRow label="Federal" sh={p.safe_harbor.federal} />
        <SafeHarborRow label={report.profile?.state_name ?? "State"} sh={p.safe_harbor.state} />
      </div>

      <div className="mt-3 flex flex-wrap gap-1.5">
        {p.due_dates.map((d, i) => (
          <span
            key={i}
            className={cn(
              "rounded-full border px-2 py-0.5 text-xs tabular-nums",
              d.status === "past"
                ? d.paid_in_window > 0 ? "border-positive/40 text-positive" : "text-muted-foreground"
                : "border-primary/40 text-primary",
            )}
          >
            {d.jurisdiction === "federal" ? "IRS" : st} {d.label} · {formatDate(d.date)}
            {d.paid_in_window > 0 && ` · ${formatCurrency(d.paid_in_window, true)}`}
          </span>
        ))}
      </div>
    </SectionCard>
  );
}

function SafeHarborRow({ label, sh }: { label: string; sh: TaxSafeHarbor }) {
  const tone =
    sh.status === "covered" ? "text-positive"
    : sh.status === "unknown" || sh.status === "not_applicable" ? "text-muted-foreground"
    : "text-warning";
  return (
    <p className="text-xs">
      <span className="font-medium">{label} safe harbor: </span>
      <span className={tone}>
        {sh.status === "covered" && (
          <>covered — {sh.paid != null && sh.required_annual != null
            ? `${formatCurrency(sh.paid)} paid vs ${formatCurrency(sh.required_annual)} required; `
            : ""}remaining balance due with the return.</>
        )}
        {sh.status === "uncovered" && (
          <>behind{sh.required_annual != null && <> — {formatCurrency(sh.paid ?? 0)} paid vs {formatCurrency(sh.required_annual)} required</>}.</>
        )}
        {sh.status === "unavailable" && <>unavailable{sh.note ? ` — ${sh.note}` : ""}.</>}
        {sh.status === "not_applicable" && <>not applicable{sh.note ? ` — ${sh.note}` : ""}.</>}
        {sh.status === "unknown" && (sh.note ?? "add prior-year tax to the profile to check.")}
      </span>
    </p>
  );
}

function ContributionsCard({ report }: { report: TaxReport }) {
  return (
    <SectionCard title="Contributions" kind="fact">
      <div className="space-y-3">
        {report.contributions.buckets.map((b) => {
          const pct = b.limit ? Math.min((b.contributed / b.limit) * 100, 100) : 0;
          return (
            <div key={b.key}>
              <div className="flex items-baseline justify-between text-sm">
                <span>{b.label}</span>
                <span className="tabular-nums text-xs text-muted-foreground">
                  {formatCurrency(b.contributed)}
                  {b.limit != null && !b.informational && <> / {formatCurrency(b.limit)}</>}
                </span>
              </div>
              {b.limit != null && !b.informational && (
                <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-muted">
                  <div
                    className={cn("h-full rounded-full", pct >= 100 ? "bg-positive" : "bg-primary")}
                    style={{ width: `${pct}%` }}
                  />
                </div>
              )}
              {b.accounts.length > 0 && (
                <p className="mt-0.5 text-xs text-muted-foreground">{b.accounts.map((a) => a.name).join(", ")}</p>
              )}
            </div>
          );
        })}
        <p className="text-xs text-muted-foreground">
          {report.contributions.note ??
            "Derived from transfers into tax-tagged accounts — payroll contributions Fin can't see can be added as a contribution adjustment."}
        </p>
      </div>
    </SectionCard>
  );
}

function WashSalesCard({ report }: { report: TaxReport }) {
  return (
    <SectionCard title="Wash-sale warnings" kind="fact">
      <div className="space-y-2">
        {report.flags.wash_sales.map((w, i) => (
          <div key={i} className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/10 px-3 py-2 text-xs">
            <TriangleAlert size={13} className="mt-0.5 shrink-0 text-warning" />
            <p>
              Loss sale of <span className="font-medium">{w.security_label}</span> ({formatCurrency(w.loss)}) on{" "}
              {formatDate(w.sale_date)} in {w.sale_account}, with a purchase on {formatDate(w.purchase_date)} in{" "}
              {w.purchase_account}.
              {w.permanent
                ? <span className="font-medium"> The purchase is in a retirement account — the loss would be disallowed permanently (Rev. Rul. 2008-5).</span>
                : " Potential wash sale — the loss may be disallowed and added to the replacement basis."}
            </p>
          </div>
        ))}
        <p className="text-xs text-muted-foreground">
          {report.flags.note ??
            "Household-wide scan across all accounts (brokers only check per account). Warnings only — your gains numbers are never silently adjusted."}
        </p>
      </div>
    </SectionCard>
  );
}

function DocumentsCard({ report, year }: { report: TaxReport; year: number }) {
  const qc = useQueryClient();
  const setStatus = useMutation({
    mutationFn: ({ id, status }: { id: string; status: string }) =>
      api.patch(`/tax/checklist_items/${id}`, { status }),
    onSuccess: () => invalidate(qc, keys.taxReport),
  });

  const docs = report.documents.items.filter((d) => d.kind !== "charitable_receipt");
  const received = docs.filter((d) => d.status === "received" || d.status === "n_a").length;

  return (
    <SectionCard
      title={`Documents (${received}/${docs.length})`}
      kind="record"
      action={<span className="text-xs text-muted-foreground">for the {year + 1} filing season</span>}
    >
      {docs.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nothing expected yet — documents seed from your accounts, loans, and equity events.</p>
      ) : (
        <div className="divide-y">
          {docs.map((d) => (
            <DocumentRow key={d.id} doc={d} onStatus={(status) => setStatus.mutate({ id: d.id, status })} />
          ))}
        </div>
      )}
    </SectionCard>
  );
}

function DocumentRow({ doc, onStatus }: { doc: TaxChecklistItem; onStatus: (s: string) => void }) {
  return (
    <div className="flex items-center gap-2 py-1.5 text-sm">
      <Badge variant="outline" className="shrink-0">{DOC_KIND_LABELS[doc.kind] ?? doc.kind}</Badge>
      <span className="min-w-0 flex-1 truncate">{doc.source_label}</span>
      {doc.notes && <span className="hidden truncate text-xs text-muted-foreground lg:inline">{doc.notes}</span>}
      <Select
        aria-label={`Status for ${doc.source_label}`}
        value={doc.status}
        onChange={(e) => onStatus(e.target.value)}
        wrapperClassName="w-28 shrink-0"
        className="h-7 text-xs"
      >
        <option value="expected">Expected</option>
        <option value="received">Received</option>
        <option value="corrected">Corrected</option>
        <option value="n_a">N/A</option>
      </Select>
    </div>
  );
}

function AdjustmentsCard({ report, onAdd, onEdit }: {
  report: TaxReport;
  onAdd: () => void;
  onEdit: (a: TaxAdjustment) => void;
}) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const rows = [
    ...report.income.adjustments.items,
    ...report.deductions.adjustments.items,
    ...(report.liability?.credits.items ?? []),
  ];

  const destroy = useMutation({
    mutationFn: (id: string) => api.delete(`/tax/adjustments/${id}`),
    onSuccess: () => {
      invalidate(qc, keys.taxReport);
      toast.success("Adjustment removed");
    },
  });

  async function handleDelete(a: TaxAdjustment) {
    if (await confirm({ title: `Remove "${a.label}"?`, confirmLabel: "Remove", destructive: true })) {
      destroy.mutate(a.id);
    }
  }

  return (
    <SectionCard
      title="Adjustments"
      kind="record"
      action={
        <Button variant="ghost" size="xs" onClick={onAdd} className="gap-1">
          <Plus size={12} />
          Add
        </Button>
      }
    >
      {rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Anything Fin doesn't track natively — K-1s, rental income, business income, payroll 401(k)
          contributions — flows into this year through adjustments. Contribution and payment adjustments
          show in their own sections.
        </p>
      ) : (
        <div className="divide-y">
          {rows.map((a) => (
            <div key={a.id} className="group flex items-center gap-2 py-1.5 text-sm">
              <Badge variant="outline" className="shrink-0">{a.kind}</Badge>
              <span className="min-w-0 flex-1 truncate">{a.label}</span>
              <span className="tabular-nums">{formatCurrency(a.amount)}</span>
              <span className="flex shrink-0 opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100">
                <Button variant="ghost" size="icon-sm" aria-label={`Edit ${a.label}`} onClick={() => onEdit(a)}>
                  <Pencil size={11} />
                </Button>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  aria-label={`Remove ${a.label}`}
                  onClick={() => handleDelete(a)}
                  className="hover:bg-destructive/10 hover:text-destructive"
                >
                  <Trash2 size={11} />
                </Button>
              </span>
            </div>
          ))}
        </div>
      )}
    </SectionCard>
  );
}
