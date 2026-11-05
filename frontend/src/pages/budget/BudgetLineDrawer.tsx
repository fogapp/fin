import { useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowUpRight } from "lucide-react";
import { mutations } from "@/api/mutations";
import { invalidateTransactionAggregates } from "@/lib/transactionCache";
import { Checkbox } from "@/components/ui/checkbox";
import { queries } from "@/api/queries";
import { monthDateRange, transactionsHref } from "@/components/charts";
import { Button } from "@/components/ui/button";
import { Drawer, DrawerContent, DrawerHeader, DrawerFooter } from "@/components/ui/drawer";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { amountColor } from "@/lib/transactions";
import { cn, formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import { budgetFillClass } from "./budgetFill";
import type { BudgetLine, BudgetLineHistoryMonth, CashTransaction } from "@/api/types";
import { formatMonthShort } from "./budgetMonth";
import { monthLabel } from "@/lib/monthLabel";
import { BudgetProgress } from "./BudgetProgress";

// Drill-down drawer for one budget line: the month's transactions in that
// category (plus any unbudgeted subcategories rolled into its actual) — the
// year's, for a yearly line — without leaving the budget page. Each
// transaction can be left out of budgets (a one-off purchase), and a
// monthly line's rollover is set here.
export function BudgetLineDrawer({ line, month, paceElapsed, onClose, onSetRollover }: {
  line: BudgetLine | null;
  month: string;
  paceElapsed: number | null;
  onClose: () => void;
  onSetRollover: (line: BudgetLine, rollover: boolean) => void;
}) {
  return (
    <Drawer open={line != null} onOpenChange={(open) => !open && onClose()}>
      {line != null && (
        <LineDrawerContent line={line} month={month} paceElapsed={paceElapsed}
                           onSetRollover={(on) => onSetRollover(line, on)} />
      )}
    </Drawer>
  );
}

function LineDrawerContent({ line, month, paceElapsed, onSetRollover }: {
  line: BudgetLine;
  month: string;
  paceElapsed: number | null;
  onSetRollover: (rollover: boolean) => void;
}) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const yearly = line.period === "yearly";
  const range = monthDateRange(month);
  const from = yearly ? `${month.slice(0, 4)}-01-01` : range.from;
  const to = range.to;

  // Match what the line's actual counts: the category itself plus unbudgeted
  // children whose spend rolls up into it.
  const categoryIds = [line.category_id, ...line.rolled_up_children.map((c) => c.category_id)];
  const { data: transactions, isLoading } = useQuery(queries.transactions({
    ...(categoryIds.length === 1
      ? { category_id: line.category_id }
      : { category_ids: categoryIds.join(",") }),
    start_date: from,
    end_date: to,
  }));

  const available = line.planned + line.rollover_amount;
  const setExcluded = useMutation({
    mutationFn: ({ id, excluded }: { id: string; excluded: boolean }) => mutations.setBudgetExcluded(id, excluded),
    onSuccess: () => invalidateTransactionAggregates(qc),
  });

  return (
    <DrawerContent className="sm:w-[430px]">
      <DrawerHeader title={line.category_name} />
      <div className="flex-1 overflow-y-auto">
        <div className="space-y-3 border-b p-4">
          <p className="text-xs text-muted-foreground">
            {yearly ? `${month.slice(0, 4)} so far · yearly budget` : monthLabel(month)}
            {line.mode === "month_only"
              ? " · one-month amount"
              : ` · set ${monthLabel(line.set_in)}`}
          </p>
          <dl className="grid grid-cols-3 gap-3 text-sm">
            <div>
              <dt className="text-xs text-muted-foreground">Spent</dt>
              <dd className="mt-0.5 tabular-nums">{formatCurrency(line.actual)}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">
                {line.rollover_amount !== 0 ? "Available" : "Planned"}
              </dt>
              <dd className="mt-0.5 tabular-nums">
                {formatCurrency(available)}
                {line.rollover_amount !== 0 && (
                  <span className="ml-1 text-xs text-muted-foreground">
                    ({formatCurrency(line.planned)} {line.rollover_amount > 0 ? "+" : "−"} {formatCurrency(Math.abs(line.rollover_amount))} rollover)
                  </span>
                )}
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Remaining</dt>
              <dd className={cn("mt-0.5 tabular-nums", moneyColor(line.remaining))}>{formatCurrency(line.remaining)}</dd>
            </div>
          </dl>
          <BudgetProgress percentUsed={line.percent_used} paceElapsed={paceElapsed} />
          {line.rolled_up_children.length > 0 && (
            <p className="text-xs text-muted-foreground">
              Includes {line.rolled_up_children.map((c) => c.name).join(", ")} — subcategories without their own budget.
            </p>
          )}
          {!yearly && (
            <label className="flex cursor-pointer items-start gap-2 text-xs text-muted-foreground">
              <Checkbox
                checked={line.rollover}
                onChange={(e) => onSetRollover(e.target.checked)}
                className="mt-0.5"
              />
              <span>
                <span className="font-medium text-foreground">Roll over</span> — carry what's left (or overspent)
                into next month
              </span>
            </label>
          )}
        </div>

        {!yearly && <LineHistory categoryId={line.category_id} month={month} />}

        {isLoading ? (
          <div className="space-y-2 p-4">
            {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-10 rounded-lg" />)}
          </div>
        ) : !transactions || transactions.length === 0 ? (
          <EmptyState className="py-12" title={yearly ? "No transactions this year" : "No transactions this month"} />
        ) : (
          <>
            <p className="px-4 pt-3 text-xs text-muted-foreground">
              A one-off purchase? Exclude it to keep it out of budgets and suggestions — it still counts in cashflow.
            </p>
            <ul className="divide-y">
              {transactions.map((tx) => (
                <TransactionRow
                  key={tx.id}
                  tx={tx}
                  onOpen={() => navigate(`/transactions/${tx.id}`)}
                  onToggleExcluded={() => setExcluded.mutate({ id: tx.id, excluded: !tx.budget_excluded })}
                />
              ))}
            </ul>
          </>
        )}
      </div>
      <DrawerFooter>
        <Button
          variant="outline"
          className="w-full"
          onClick={() => navigate(transactionsHref({ categoryId: line.category_id, month }))}
        >
          <ArrowUpRight size={14} />
          View in Transactions
        </Button>
      </DrawerFooter>
    </DrawerContent>
  );
}

// Trailing months of planned vs actual — the same bullet visual as the
// Budget vs. actual chart (grey actual fill, planned tick), scaled to a
// shared dollar axis so month-to-month magnitudes stay comparable.
function LineHistory({ categoryId, month }: { categoryId: string; month: string }) {
  const { data, isLoading } = useQuery(queries.budgetLineHistory(month, categoryId));

  if (isLoading) {
    return (
      <div className="space-y-2 border-b p-4">
        {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-5 rounded" />)}
      </div>
    );
  }

  const months: BudgetLineHistoryMonth[] = data?.months ?? [];
  // Hide the section when there's no history to compare against — a brand-new
  // category's empty rows would just be noise.
  if (!months.slice(0, -1).some((m) => m.planned > 0 || m.actual > 0)) return null;

  const axisMax = Math.max(...months.map((m) => Math.max(m.planned, m.actual))) * 1.05;

  return (
    <div className="border-b p-4">
      <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Recent Months</p>
      <div className="space-y-1">
        {months.map((m, i) => {
          const current = i === months.length - 1;
          const pct = m.planned > 0 ? (m.actual / m.planned) * 100 : null;
          const fill = budgetFillClass(pct);

          return (
            <div key={m.month} className="grid grid-cols-[3.5rem_1fr_auto] items-center gap-3 py-0.5">
              <span className={cn("text-xs tabular-nums", current ? "font-medium" : "text-muted-foreground")}>
                {formatMonthShort(m.month)}
              </span>
              <span className="relative block h-2">
                <span className="absolute inset-0 overflow-hidden rounded-full bg-muted">
                  <span
                    className={cn("block h-full rounded-full", fill)}
                    style={{ width: `${axisMax > 0 ? Math.min((m.actual / axisMax) * 100, 100) : 0}%` }}
                  />
                </span>
                {m.planned > 0 && (
                  <span
                    className="absolute top-1/2 h-3.5 w-0.5 -translate-y-1/2 rounded-full bg-foreground/60"
                    style={{ left: `calc(${Math.min((m.planned / axisMax) * 100, 100)}% - 1px)` }}
                  />
                )}
              </span>
              <span className="whitespace-nowrap text-xs tabular-nums text-muted-foreground">
                {formatCurrency(m.actual)}
                <span className="text-muted-foreground/60"> / {m.planned > 0 ? formatCurrency(m.planned) : "—"}</span>
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function TransactionRow({ tx, onOpen, onToggleExcluded }: {
  tx: CashTransaction;
  onOpen: () => void;
  onToggleExcluded: () => void;
}) {
  const excluded = tx.budget_excluded;
  return (
    <li className="flex items-center">
      <button
        onClick={onOpen}
        className="flex min-w-0 flex-1 items-center gap-3 py-2.5 pl-4 pr-2 text-left text-sm transition-colors hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
      >
        <div className={cn("min-w-0 flex-1", excluded && "opacity-60")}>
          <p className="truncate">{tx.merchant_name ?? tx.description}</p>
          <p className="truncate text-xs text-muted-foreground">
            {formatDate(tx.transaction_date)}
            {tx.account_name ? ` · ${tx.account_name}` : ""}
            {excluded && " · excluded from budget"}
          </p>
        </div>
        <span className={cn("shrink-0 tabular-nums", excluded ? "text-muted-foreground line-through" : amountColor(tx))}>
          {formatCurrency(tx.amount)}
        </span>
      </button>
      <button
        type="button"
        onClick={onToggleExcluded}
        className="mr-2 shrink-0 rounded px-1.5 py-1 text-xs text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        aria-label={excluded ? `Count ${tx.merchant_name ?? tx.description} in budgets` : `Exclude ${tx.merchant_name ?? tx.description} from budgets`}
        title={excluded ? "Count this in budgets again" : "Leave this out of budgets (a one-off purchase)"}
      >
        {excluded ? "Include" : "Exclude"}
      </button>
    </li>
  );
}
