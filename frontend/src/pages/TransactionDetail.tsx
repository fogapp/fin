import { useParams, Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, ArrowLeftRight, Copy, Repeat, Search, Sparkles, TrendingUp, Undo2, Wallet } from "lucide-react";
import { queries } from "@/api/queries";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { PageHeader } from "@/components/layout/PageHeader";
import { useTransferState } from "@/components/transaction/useTransferState";
import { cn, formatCurrency } from "@/lib/utils";
import { amountColor, normalizeDescription, transferKindLabel } from "@/lib/transactions";
import { searchEngineById, searchUrl } from "@/lib/searchEngines";
import { useTransactionDefaults } from "@/hooks/useTransactionDefaults";
import type { CashTransaction, TransactionContext } from "@/api/types";
import { insights, scrollToSection, type Insight } from "./transaction/insights";
import { HistorySection } from "./transaction/HistorySection";
import { RecurrenceSection } from "./transaction/RecurrenceSection";
import { BudgetSection } from "./transaction/BudgetSection";
import { AroundSection } from "./transaction/AroundSection";
import { ManageRail } from "./transaction/ManageRail";

// ── Transaction page ──────────────────────────────────────────────────────────
// Two halves with one job each. The left tells the row's story against the
// rest of the household's money — is it normal, does it repeat, what did it
// do to the budget, what happened around it — each section leading with the
// sentence it found. The right is the one panel of tools to act on it, with
// the decisions the story surfaced at the top. Insight chips under the header
// summarize the story and jump to the section that explains each.

export function TransactionDetail() {
  const { id } = useParams<{ id: string }>();
  const { data: txn, isLoading, error, refetch } = useQuery({ ...queries.transaction(id!), enabled: !!id });
  const context = useQuery({ ...queries.transactionContext(id!), enabled: !!id });

  if (isLoading) return <Loading />;
  if (error || !txn) return <ErrorState title="Transaction not found" onRetry={() => refetch()} />;

  const ctx = context.data;

  return (
    <div className="flex flex-col">
      <PageHeader title="Transaction" level={2} back={{ to: "/transactions", label: "Back to transactions" }} />

      <div className="mx-auto w-full max-w-6xl space-y-6 p-4 sm:p-6">
        <Hero tx={txn} ctx={ctx} />

        <div className="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
          <div className="min-w-0 divide-y">
            {context.isLoading && <StorySkeleton />}
            {context.isError && (
              <ErrorState title="Couldn't load this transaction's history" onRetry={() => context.refetch()} />
            )}
            {ctx && (
              <>
                <HistorySection tx={txn} ctx={ctx} />
                <RecurrenceSection tx={txn} ctx={ctx} />
                <BudgetSection ctx={ctx} />
                <AroundSection tx={txn} ctx={ctx} />
              </>
            )}
          </div>

          <div className="lg:sticky lg:top-4">
            <ManageRail tx={txn} ctx={ctx} />
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Hero ──────────────────────────────────────────────────────────────────────

function Hero({ tx, ctx }: { tx: CashTransaction; ctx: TransactionContext | undefined }) {
  const { counterpartyName } = useTransferState(tx);
  const name = tx.merchant_name ?? (normalizeDescription(tx.description) || tx.description || "—");
  const kind = tx.transfer_id
    ? `${transferKindLabel(tx.transfer_kind)}${counterpartyName ? ` ${tx.amount > 0 ? "from" : "to"} ${counterpartyName}` : ""}`
    : tx.amount > 0 ? "Money in" : "Money out";
  const chips = ctx ? insights(tx, ctx) : [];

  return (
    <header className="space-y-4">
      <div className="flex items-start gap-4">
        <span aria-hidden className="flex size-12 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-lg font-semibold text-primary">
          {name.trim().charAt(0).toUpperCase() || "?"}
        </span>
        <div className="min-w-0 flex-1 space-y-1">
          <h1 className="truncate text-xl font-semibold leading-tight sm:text-2xl">{name}</h1>
          <p className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-sm text-muted-foreground">
            <Descriptor description={tx.description} />
            {tx.account_name && (
              <>
                <span aria-hidden>·</span>
                {tx.account_id
                  ? <Link to={`/accounts#id=${tx.account_id}`} className="hover:text-foreground hover:underline">{tx.account_name}</Link>
                  : tx.account_name}
              </>
            )}
            <span aria-hidden>·</span>
            <span>{longDate(tx.transaction_date)}</span>
          </p>
        </div>
        <div className="shrink-0 text-right">
          <p className={cn("text-2xl font-semibold leading-tight sm:text-3xl", amountColor(tx))}>{formatCurrency(tx.amount)}</p>
          <p className="text-xs text-muted-foreground">{kind}</p>
        </div>
      </div>

      {chips.length > 0 && (
        <ul className="flex flex-wrap gap-2" aria-label="What stands out">
          {chips.map((c) => <li key={c.key}><Chip insight={c} /></li>)}
        </ul>
      )}
    </header>
  );
}

const CHIP_ICON: Record<string, React.ComponentType<{ size?: number }>> = {
  amount: TrendingUp, first: Sparkles, series: Repeat, cadence: Repeat, duplicate: Copy,
  refund: Undo2, budget: Wallet, excluded: ArrowLeftRight, over: AlertTriangle,
};

function Chip({ insight }: { insight: Insight }) {
  const Icon = CHIP_ICON[insight.key] ?? Sparkles;
  return (
    <Button
      size="xs"
      variant="outline"
      onClick={() => scrollToSection(insight.target)}
      className={cn(
        "rounded-full font-normal",
        insight.tone === "warning" && "border-warning/40 bg-warning/10 text-warning hover:bg-warning/15",
        insight.tone === "positive" && "border-positive/40 bg-positive/10 text-positive hover:bg-positive/15",
      )}
    >
      <Icon size={12} />
      {insight.label}
    </Button>
  );
}

/** The raw bank descriptor doubles as a web search — often the only way to
 *  work out what "SQ *SOME SHOP 8005551234" was. Engine from Settings. */
function Descriptor({ description }: { description: string | null }) {
  const { searchEngine } = useTransactionDefaults();
  const query = (description ?? "").trim();
  if (!query) return <span>No description</span>;
  const engine = searchEngineById(searchEngine);
  return (
    <a
      href={searchUrl(searchEngine, query)}
      target="_blank"
      rel="noopener noreferrer"
      title={`Search ${engine.label} for "${query}"`}
      className="group inline-flex min-w-0 items-center gap-1 rounded font-mono text-xs hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <span className="truncate">{description}</span>
      <Search size={11} aria-hidden className="shrink-0 transition-colors group-hover:text-primary" />
    </a>
  );
}

function longDate(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric" });
}

// ── Loading ───────────────────────────────────────────────────────────────────

function StorySkeleton() {
  return (
    <div className="space-y-4">
      <Skeleton className="h-4 w-40" />
      <Skeleton className="h-5 w-72" />
      <Skeleton className="h-44 rounded-xl" />
      <Skeleton className="h-24 rounded-xl" />
    </div>
  );
}

function Loading() {
  return (
    <div className="flex flex-col">
      <div className="flex h-14 items-center gap-3 border-b px-6">
        <Skeleton className="h-4 w-4" />
        <Skeleton className="h-5 w-56" />
      </div>
      <div className="mx-auto w-full max-w-6xl space-y-6 p-6">
        <div className="flex items-start gap-4">
          <Skeleton className="size-12 rounded-xl" />
          <div className="flex-1 space-y-2"><Skeleton className="h-6 w-64" /><Skeleton className="h-4 w-96" /></div>
          <Skeleton className="h-8 w-28" />
        </div>
        <div className="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <StorySkeleton />
          <Skeleton className="h-96 rounded-xl" />
        </div>
      </div>
    </div>
  );
}
