import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Link, ChevronDown, ChevronUp, Trash2, Pencil } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { useLoanPatch } from "@/hooks/useLoanPatch";
import { formatCurrency, formatDate } from "@/lib/utils";
import { StatRibbon } from "@/components/StatRibbon";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Field, FieldError } from "@/components/ui/field";
import { useConfirm } from "@/components/ui/confirm";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton, SkeletonList } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { PageHeader } from "@/components/layout/PageHeader";
import type { PageAction } from "@/components/layout/PageHeader";
import { ResponsiveTransactionView } from "@/components/TransactionList";
import type { AmortizationEntry, LoanDetail as LoanDetailType } from "@/api/types";
import { ESCROW_FIELDS, parseOptionalAmount } from "./loans/escrow";
import { LoanForm } from "./loans/LoanForm";
import type { EscrowField } from "./loans/escrow";
import { invalidate, keys } from "@/api/keys";

export function LoanDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();

  const { data: loan, isLoading, error, refetch } = useQuery(queries.loan(id!));
  const deleteAction = useDeleteLoanAction(id!, () => navigate("/loans"));
  const [editing, setEditing] = useState(false);

  if (isLoading) return <Loading />;
  if (error || !loan) return (
    <ErrorState title="Failed to load loan." onRetry={() => refetch()} />
  );

  const pctPaid = loan.original_principal > 0
    ? ((loan.original_principal - loan.current_balance) / loan.original_principal) * 100
    : 0;

  const payoffEntry = loan.amortization_schedule[loan.amortization_schedule.length - 1];

  return (
    <div className="flex flex-col h-full">
      <PageHeader
        level={2}
        title={loan.name}
        subtitle={loan.merchant_name ?? loan.lender ?? undefined}
        back={{ to: "/loans", label: "Loans" }}
        actions={[
          { label: "Edit loan", icon: Pencil, onSelect: () => setEditing(true) },
          { ...deleteAction, separatorBefore: true },
        ]}
      >
        <LoanTypeBadge type={loan.loan_type} />
        {loan.status !== "active" && (
          <span className="rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground capitalize">
            {loan.status.replace("_", " ")}
          </span>
        )}
        <InterestOnlyToggle loanId={loan.id} value={loan.interest_only} />
      </PageHeader>

      {/* Stats ribbon */}
      <StatRibbon borderTop={false} stats={[
        { label: "Outstanding Balance", value: formatCurrency(loan.current_balance) },
        { label: "Original Principal",  value: formatCurrency(loan.original_principal) },
        { label: "Interest Rate",       value: `${loan.interest_rate.toFixed(3)}% APR` },
        { label: "Monthly Payment",     value: formatCurrency(loan.monthly_payment) },
        { label: "Term",                value: `${loan.term_months} mo` },
        { label: "Started",             value: formatDate(loan.start_date) },
        ...(payoffEntry ? [{ label: "Payoff Date", value: formatDate(payoffEntry.payment_date) }] : []),
      ]} />

      <div className="flex-1 overflow-y-auto space-y-6 p-6">
        {editing && (
          <LoanForm loan={loan} onSaved={() => setEditing(false)} onCancel={() => setEditing(false)} />
        )}

        {/* Progress */}
        <Card>
          <CardContent className="p-5">
            <div className="mb-3 flex items-center justify-between text-sm">
              <span className="font-medium">Payoff Progress</span>
              <span className="text-muted-foreground tabular-nums">{pctPaid.toFixed(1)}% paid</span>
            </div>
            <div className="h-2 w-full rounded-full bg-muted overflow-hidden">
              <div
                className="h-full rounded-full bg-primary transition-all"
                style={{ width: `${Math.min(pctPaid, 100).toFixed(2)}%` }}
              />
            </div>
            <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
              <Metric label="Principal Paid" value={formatCurrency(loan.principal_paid)} />
              <Metric label="Interest Paid" value={formatCurrency(loan.interest_paid)} />
              <Metric label="Total Paid" value={formatCurrency(loan.total_paid)} />
              <Metric label="Total Interest (scheduled)" value={formatCurrency(loan.total_scheduled_interest)} />
            </div>
            {loan.account_name && (
              <p className="mt-4 text-xs text-muted-foreground">
                Linked account: <span className="text-foreground">{loan.account_name}</span>
              </p>
            )}
          </CardContent>
        </Card>

        {/* Payment breakdown: principal & interest vs. escrow */}
        <PaymentBreakdownCard loan={loan} />

        {/* Balance anchor */}
        <BalanceAnchorCard loan={loan} />

        {/* Linked payments */}
        <div>
          <div className="mb-2 flex items-center justify-between">
            <h2 className="text-sm font-semibold">Linked Payments</h2>
            <LinkTransactionButton loanId={loan.id} />
          </div>
          <LinkedPaymentsTable loanId={loan.id} />
        </div>

        {/* Amortization schedule */}
        <AmortizationTable loanId={loan.id} schedule={loan.amortization_schedule} paymentsCount={loan.payments_count} />
      </div>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-sm font-semibold tabular-nums">{value}</p>
    </div>
  );
}

function LoanTypeBadge({ type }: { type: string }) {
  return (
    <span className="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary capitalize">
      {type}
    </span>
  );
}

function PaymentBreakdownCard({ loan }: { loan: LoanDetailType }) {
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<Record<"monthly_payment" | EscrowField, string>>({
    monthly_payment: "", escrow_property_tax: "", escrow_insurance: "", escrow_other: "",
  });
  const [error, setError] = useState("");

  function startEdit() {
    const amount = (value: number | null) => (value != null ? String(value) : "");
    setForm({
      monthly_payment:     amount(loan.entered_monthly_payment),
      escrow_property_tax: amount(loan.escrow_property_tax),
      escrow_insurance:    amount(loan.escrow_insurance),
      escrow_other:        amount(loan.escrow_other),
    });
    setError("");
    setEditing(true);
  }

  const save = useLoanPatch(loan.id, {
    onSuccess: () => setEditing(false),
    onError: (e) => setError(e.message),
  });

  const escrowLines = ESCROW_FIELDS.filter(({ key }) => (loan[key] ?? 0) > 0);

  const draftEscrow = ESCROW_FIELDS.reduce((sum, { key }) => sum + (parseOptionalAmount(form[key]) ?? 0), 0);
  const draftPayment = parseOptionalAmount(form.monthly_payment);

  return (
    <Card>
      <CardContent className="p-5">
        <div className="flex items-center justify-between text-sm">
          <div>
            <span className="font-medium">Monthly Payment</span>
            <p className="mt-0.5 text-xs text-muted-foreground">
              Escrowed property taxes and insurance are taken out of each payment before the rest is applied to the loan.
            </p>
          </div>
          {!editing && (
            <Button
              variant="ghost"
              size="xs"
              onClick={startEdit}
              aria-label="Edit monthly payment"
              className="text-muted-foreground hover:text-foreground"
            >
              <Pencil size={12} />
              Edit
            </Button>
          )}
        </div>

        {!editing && (
          <dl className="mt-3 divide-y text-sm">
            <div className="flex items-baseline justify-between gap-4 py-1.5">
              <dt className="text-muted-foreground">Principal &amp; interest</dt>
              <dd className="tabular-nums">{formatCurrency(loan.principal_and_interest_payment)}/mo</dd>
            </div>
            {escrowLines.map(({ key, label, paidKey }) => (
              <div key={key} className="flex items-baseline justify-between gap-4 py-1.5">
                <dt className="text-muted-foreground">{label}</dt>
                <dd className="text-right tabular-nums">
                  {formatCurrency(loan[key] ?? 0)}/mo
                  <span className="ml-3 text-xs text-muted-foreground">{formatCurrency(loan[paidKey])} paid to date</span>
                </dd>
              </div>
            ))}
            {escrowLines.length > 0 && (
              <div className="flex items-baseline justify-between gap-4 py-1.5 font-medium">
                <dt>Total</dt>
                <dd className="tabular-nums">{formatCurrency(loan.monthly_payment)}/mo</dd>
              </div>
            )}
          </dl>
        )}

        {!editing && escrowLines.length === 0 && (
          <p className="mt-2 text-xs text-muted-foreground italic">
            No escrow recorded — if your payment includes property taxes or insurance, add them so they don&rsquo;t count toward the payoff.
          </p>
        )}

        {editing && (
          <form
            className="mt-4 space-y-3"
            onSubmit={(e) => {
              e.preventDefault();
              setError("");
              save.mutate({
                monthly_payment:     parseOptionalAmount(form.monthly_payment),
                escrow_property_tax: parseOptionalAmount(form.escrow_property_tax),
                escrow_insurance:    parseOptionalAmount(form.escrow_insurance),
                escrow_other:        parseOptionalAmount(form.escrow_other),
              });
            }}
          >
            <div className="grid gap-3 sm:grid-cols-4">
              <Field label="Monthly payment" htmlFor="payment-total">
                <Input
                  id="payment-total"
                  autoFocus
                  type="number"
                  step="0.01"
                  min="0"
                  value={form.monthly_payment}
                  onChange={(e) => setForm((f) => ({ ...f, monthly_payment: e.target.value }))}
                  placeholder="Auto-computed"
                  className="tabular-nums"
                />
              </Field>
              {ESCROW_FIELDS.map(({ key, label }) => (
                <Field key={key} label={label} htmlFor={`payment-${key}`}>
                  <Input
                    id={`payment-${key}`}
                    type="number"
                    step="0.01"
                    min="0"
                    value={form[key]}
                    onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
                    placeholder="0.00"
                    className="tabular-nums"
                  />
                </Field>
              ))}
            </div>
            <p className="text-xs text-muted-foreground">
              {draftPayment != null
                ? `Principal & interest: ${formatCurrency(Math.max(draftPayment - draftEscrow, 0))}/mo`
                : "Leave the payment blank to compute principal and interest from the rate and term."}
            </p>
            <FieldError>{error}</FieldError>
            <div className="flex items-center justify-end gap-2">
              <Button
                type="button"
                variant="ghost"
                size="xs"
                onClick={() => setEditing(false)}
                className="text-muted-foreground hover:text-foreground"
              >
                Cancel
              </Button>
              <Button type="submit" size="xs" disabled={save.isPending}>
                Save
              </Button>
            </div>
          </form>
        )}
      </CardContent>
    </Card>
  );
}

function BalanceAnchorCard({ loan }: { loan: LoanDetailType }) {
  const [editing, setEditing] = useState(false);
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState("");
  const [error, setError] = useState("");

  function startEdit() {
    setAmount(loan.balance_anchor_amount != null ? String(loan.balance_anchor_amount) : "");
    setDate(loan.balance_anchor_date ?? "");
    setError("");
    setEditing(true);
  }

  const save = useLoanPatch(loan.id, {
    onSuccess: () => setEditing(false),
    onError: (e) => setError(e.message),
  });
  const clear = useLoanPatch(loan.id, { onSuccess: () => setEditing(false) });

  return (
    <Card>
      <CardContent className="p-5">
        <div className="flex items-center justify-between text-sm">
          <div>
            <span className="font-medium">Known Balance</span>
            <p className="mt-0.5 text-xs text-muted-foreground">
              Set a known remaining balance at a specific date. Future linked payments will be calculated from this starting point.
            </p>
          </div>
          {!editing && (
            <Button
              variant="ghost"
              size="xs"
              onClick={startEdit}
              className="text-muted-foreground hover:text-foreground"
            >
              <Pencil size={12} />
              {loan.balance_anchor_amount != null ? "Edit" : "Set"}
            </Button>
          )}
        </div>

        {!editing && loan.balance_anchor_amount != null && (
          <div className="mt-3 flex items-baseline gap-3">
            <span className="text-lg font-semibold tabular-nums">{formatCurrency(loan.balance_anchor_amount)}</span>
            <span className="text-xs text-muted-foreground">as of {formatDate(loan.balance_anchor_date!)}</span>
          </div>
        )}

        {!editing && loan.balance_anchor_amount == null && (
          <p className="mt-2 text-xs text-muted-foreground italic">Not set — balance calculated from original principal and all linked payments.</p>
        )}

        {editing && (
          <form
            className="mt-4 space-y-3"
            onSubmit={(e) => {
              e.preventDefault();
              setError("");
              save.mutate({ balance_anchor_amount: parseFloat(amount), balance_anchor_date: date });
            }}
          >
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="Remaining balance ($)" htmlFor="anchor-amount">
                <Input
                  id="anchor-amount"
                  required
                  autoFocus
                  type="number"
                  step="0.01"
                  min="0"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="14624.55"
                  className="tabular-nums"
                />
              </Field>
              <Field label="As of date" htmlFor="anchor-date">
                <Input
                  id="anchor-date"
                  required
                  type="date"
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                />
              </Field>
            </div>
            <FieldError>{error}</FieldError>
            <div className="flex items-center gap-2">
              {loan.balance_anchor_amount != null && (
                <Button
                  type="button"
                  variant="ghost"
                  size="xs"
                  onClick={() => clear.mutate({ balance_anchor_amount: null, balance_anchor_date: null })}
                  disabled={clear.isPending}
                  className="mr-auto text-destructive hover:bg-destructive/10"
                >
                  Clear
                </Button>
              )}
              <Button
                type="button"
                variant="ghost"
                size="xs"
                onClick={() => setEditing(false)}
                className="text-muted-foreground hover:text-foreground"
              >
                Cancel
              </Button>
              <Button type="submit" size="xs" disabled={save.isPending}>
                Save
              </Button>
            </div>
          </form>
        )}
      </CardContent>
    </Card>
  );
}

function InterestOnlyToggle({ loanId, value }: { loanId: string; value: boolean }) {
  const toggle = useLoanPatch(loanId);
  return (
    <Button
      variant="ghost"
      size="xs"
      onClick={() => toggle.mutate({ interest_only: !value })}
      disabled={toggle.isPending}
      className={value ? "bg-accent text-foreground hover:bg-accent/80" : "text-muted-foreground hover:text-foreground"}
      title={value ? "Switch to amortizing" : "Switch to interest-only"}
    >
      {value ? "Interest only" : "Amortizing"}
    </Button>
  );
}

function useDeleteLoanAction(loanId: string, onDeleted: () => void): PageAction {
  const qc = useQueryClient();
  const confirm = useConfirm();

  const destroy = useMutation({
    mutationFn: () => api.delete(`/loans/${loanId}`),
    onSuccess: () => {
      invalidate(qc, keys.loans);
      onDeleted();
    },
  });

  return {
    label: "Delete loan",
    icon: Trash2,
    destructive: true,
    disabled: destroy.isPending,
    onSelect: async () => {
      if (await confirm({
        title: "Delete this loan?",
        description: "The loan and its amortization schedule are removed. Linked transactions are kept.",
        confirmLabel: "Delete loan",
        destructive: true,
      })) {
        destroy.mutate();
      }
    },
  };
}

function LinkedPaymentsTable({ loanId }: { loanId: string }) {
  const { data: transactions = [], isLoading } = useQuery(queries.loanTransactions(loanId));

  if (!isLoading && transactions.length === 0) {
    return (
      <Card>
        <CardContent className="p-0">
          <EmptyState
            title="No transactions linked yet."
            description="Use the button above to link payments from your transaction history."
          />
        </CardContent>
      </Card>
    );
  }

  return (
    <ResponsiveTransactionView transactions={transactions} isLoading={isLoading} resetKey={loanId} />
  );
}

function LinkTransactionButton({ loanId }: { loanId: string }) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");

  const { data: candidates = [], isLoading } = useQuery({
    ...queries.loanCandidates(loanId),
    enabled: open,
  });

  const link = useMutation({
    mutationFn: (txId: string) => api.patch(`/cash_transactions/${txId}`, { loan_id: loanId }),
    onSuccess: () => {
      // ["loans"] covers the list balance, this detail and its candidates.
      invalidate(qc, keys.loans, queries.loanTransactions(loanId).queryKey);
    },
  });

  const filtered = candidates.filter((t) =>
    !search || t.description.toLowerCase().includes(search.toLowerCase())
  );

  const trigger = (
    <Button
      variant="ghost"
      size="xs"
      onClick={() => setOpen((v) => !v)}
      className="text-muted-foreground hover:text-foreground"
    >
      <Link size={13} />
      Link payment
    </Button>
  );

  if (!open) return trigger;

  return (
    <div className="relative">
      {trigger}
      <div className="absolute right-0 top-full z-20 mt-1 w-96 rounded-xl border bg-card shadow-lg">
        <div className="border-b px-3 py-2">
          <input
            autoFocus
            aria-label="Search transactions"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search transactions…"
            className="flex h-7 w-full rounded-lg border-0 bg-transparent text-sm placeholder:text-muted-foreground focus:outline-none"
          />
        </div>
        <div className="max-h-72 overflow-y-auto">
          {isLoading && (
            <SkeletonList rows={3} className="space-y-2 px-4 py-3" rowClassName="h-6" />
          )}
          {!isLoading && filtered.length === 0 && (
            <p className="px-4 py-3 text-xs text-muted-foreground">No matching transactions.</p>
          )}
          {filtered.map((t) => (
            <button
              key={t.id}
              onClick={() => { link.mutate(t.id); setOpen(false); setSearch(""); }}
              disabled={link.isPending}
              className="flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left text-sm hover:bg-accent disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-inset"
            >
              <span className="flex flex-col min-w-0">
                <span className="truncate font-medium">{t.description}</span>
                <span className="text-tiny text-muted-foreground">{formatDate(t.transaction_date)} · {t.account_name}</span>
              </span>
              <span className="shrink-0 tabular-nums font-medium">{formatCurrency(Math.abs(t.amount))}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

function AmortizationTable({ schedule, paymentsCount }: { loanId: string; schedule: AmortizationEntry[]; paymentsCount: number }) {
  const [expanded, setExpanded] = useState(false);
  const showEscrow = schedule.some((row) => row.escrow > 0);

  const displayedRows = expanded ? schedule : schedule.slice(0, 24);

  return (
    <div>
      <div className="mb-2 flex items-center justify-between">
        <h2 className="text-sm font-semibold">Amortization Schedule</h2>
        <span className="text-xs text-muted-foreground">{schedule.length} payments</span>
      </div>
      <Card>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-xs text-muted-foreground">
                  <th className="px-4 py-2.5 text-right font-medium">#</th>
                  <th className="px-4 py-2.5 text-left font-medium">Date</th>
                  <th className="px-4 py-2.5 text-right font-medium">Payment</th>
                  <th className="px-4 py-2.5 text-right font-medium">Principal</th>
                  <th className="px-4 py-2.5 text-right font-medium">Interest</th>
                  {showEscrow && <th className="px-4 py-2.5 text-right font-medium">Escrow</th>}
                  <th className="px-4 py-2.5 text-right font-medium">Balance</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {displayedRows.map((row) => {
                  const isPaid = row.payment_number <= paymentsCount;
                  return (
                    <tr
                      key={row.payment_number}
                      className={isPaid ? "bg-muted/30 text-muted-foreground" : ""}
                    >
                      <td className="px-4 py-2 text-right tabular-nums text-xs text-muted-foreground">{row.payment_number}</td>
                      <td className="px-4 py-2 tabular-nums">{formatDate(row.payment_date)}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatCurrency(row.payment)}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatCurrency(row.principal)}</td>
                      <td className="px-4 py-2 text-right tabular-nums text-muted-foreground">{formatCurrency(row.interest)}</td>
                      {showEscrow && (
                        <td className="px-4 py-2 text-right tabular-nums text-muted-foreground">{formatCurrency(row.escrow)}</td>
                      )}
                      <td className="px-4 py-2 text-right tabular-nums font-medium">{formatCurrency(row.balance)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          {schedule.length > 24 && (
            <button
              onClick={() => setExpanded((v) => !v)}
              className="flex w-full items-center justify-center gap-1.5 border-t px-4 py-2.5 text-xs text-muted-foreground hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-inset"
            >
              {expanded ? <ChevronUp size={13} /> : <ChevronDown size={13} />}
              {expanded ? "Show fewer" : `Show all ${schedule.length} payments`}
            </button>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function Loading() {
  return (
    <div className="flex-1 overflow-y-auto space-y-6 p-6">
      <Skeleton className="h-5 w-40" />
      <Skeleton className="h-10 w-full rounded-lg" />
      <Skeleton className="h-32 rounded-xl" />
      <Skeleton className="h-48 rounded-xl" />
      <Skeleton className="h-64 rounded-xl" />
    </div>
  );
}
