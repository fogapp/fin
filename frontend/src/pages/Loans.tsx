import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Landmark, Plus, X, ChevronRight } from "lucide-react";
import { queries } from "@/api/queries";
import { formatCurrency } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { PageHeader } from "@/components/layout/PageHeader";
import type { Loan } from "@/api/types";
import { LoanForm } from "./loans/LoanForm";

export function Loans() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const prefillAccountId = searchParams.get("account_id") ?? "";
  const prefillName = searchParams.get("name") ?? "";
  const [showForm, setShowForm] = useState(prefillAccountId !== "");
  const { data: loans = [], isLoading, isError, refetch } = useQuery(queries.loans());

  // Re-open the form when navigation adds ?account_id (adjust-state-during-render
  // pattern; see react.dev "You Might Not Need an Effect").
  const [prevPrefillAccountId, setPrevPrefillAccountId] = useState(prefillAccountId);
  if (prevPrefillAccountId !== prefillAccountId) {
    setPrevPrefillAccountId(prefillAccountId);
    if (prefillAccountId) setShowForm(true);
  }

  const totalBalance = loans.reduce((s, l) => s + l.current_balance, 0);
  const totalMonthly = loans.filter(l => l.status === "active").reduce((s, l) => s + l.monthly_payment, 0);

  return (
    <div className="flex flex-col h-full">
      <PageHeader
        title="Loans"
        level={1}
        actions={[
          showForm
            ? { label: "Cancel new loan", icon: X, onSelect: () => setShowForm(false) }
            : { label: "New loan", icon: Plus, onSelect: () => setShowForm(true) },
        ]}
      />

      {/* Summary bar */}
      {!isError && loans.length > 0 && (
        <div className="flex shrink-0 gap-x-1 border-b bg-card px-4">
          <StatChip label="Total Outstanding" value={formatCurrency(totalBalance)} />
          <span className="text-border select-none self-center">·</span>
          <StatChip label="Monthly Payments" value={formatCurrency(totalMonthly)} />
          <span className="text-border select-none self-center">·</span>
          <StatChip label="Active Loans" value={String(loans.filter(l => l.status === "active").length)} />
        </div>
      )}

      {isError ? (
        <div className="flex-1">
          <ErrorState title="Failed to load loans" onRetry={() => refetch()} />
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto p-6 space-y-4">
          {showForm && (
            <LoanForm
              initialAccountId={prefillAccountId}
              initialName={prefillName}
              onSaved={(loan) => { setShowForm(false); setSearchParams({}); navigate(`/loans/${loan.id}`); }}
              onCancel={() => setShowForm(false)}
            />
          )}

          {isLoading && (
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-28 rounded-xl" />
              ))}
            </div>
          )}

          {!isLoading && loans.length === 0 && !showForm && (
            <EmptyState
              icon={Landmark}
              title="No loans yet."
              description="Add one to start tracking debt."
              action={
                <Button size="sm" onClick={() => setShowForm(true)}>
                  <Plus size={14} />
                  New loan
                </Button>
              }
            />
          )}

          {loans.map((loan) => (
            <LoanCard key={loan.id} loan={loan} onClick={() => navigate(`/loans/${loan.id}`)} />
          ))}
        </div>
      )}
    </div>
  );
}

function StatChip({ label, value }: { label: string; value: string }) {
  return (
    <span className="flex flex-col px-3 py-2.5 shrink-0">
      <span className="text-sm font-semibold tabular-nums leading-tight">{value}</span>
      <span className="text-tiny text-muted-foreground leading-tight">{label}</span>
    </span>
  );
}

function LoanCard({ loan, onClick }: { loan: Loan; onClick: () => void }) {
  // Match LoanDetail: balance-based so loans with a balance anchor agree with the detail page.
  const pctPaid = loan.original_principal > 0
    ? ((loan.original_principal - loan.current_balance) / loan.original_principal) * 100
    : 0;

  return (
    <button
      onClick={onClick}
      className="w-full text-left rounded-xl border bg-card p-5 hover:bg-accent/40 transition-colors group focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="font-semibold truncate">{loan.name}</span>
            <LoanTypeBadge type={loan.loan_type} />
            {loan.status !== "active" && (
              <span className="rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground capitalize">
                {loan.status.replace("_", " ")}
              </span>
            )}
          </div>
          {(loan.merchant_name ?? loan.lender) && (
            <p className="mt-0.5 text-xs text-muted-foreground truncate">{loan.merchant_name ?? loan.lender}</p>
          )}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <div className="text-right">
            <p className="text-sm font-semibold tabular-nums">{formatCurrency(loan.current_balance)}</p>
            <p className="text-tiny text-muted-foreground">remaining</p>
          </div>
          <ChevronRight size={14} className="text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
        </div>
      </div>

      {/* Progress bar */}
      <div className="mt-4 space-y-1.5">
        <div className="h-1.5 w-full rounded-full bg-muted overflow-hidden">
          <div
            className="h-full rounded-full bg-primary transition-all"
            style={{ width: `${Math.min(pctPaid, 100).toFixed(1)}%` }}
          />
        </div>
        <div className="flex justify-between text-tiny text-muted-foreground tabular-nums">
          <span>{pctPaid.toFixed(1)}% paid off</span>
          <span>{loan.interest_rate.toFixed(3)}% APR · {formatCurrency(loan.monthly_payment)}/mo</span>
        </div>
      </div>
    </button>
  );
}

function LoanTypeBadge({ type }: { type: string }) {
  return (
    <span className="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary capitalize">
      {type}
    </span>
  );
}
