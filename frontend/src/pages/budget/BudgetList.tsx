import { ChevronRight, RotateCcw } from "lucide-react";
import { cn, formatCurrency, moneyColor } from "@/lib/utils";
import type { BudgetData, BudgetLine } from "@/api/types";
import { BudgetProgress } from "./BudgetProgress";
import { available, groupLines } from "./budgetGroups";
import { formatMonthShort } from "./budgetMonth";

/**
 * The month's budget as one list: each budgeted category (subcategories
 * nested under their parent), then "Everything else" — the catch-all for
 * spending in categories without a budget — then yearly budgets measured
 * year to date. Rows open the drill-down drawer.
 */
export function BudgetList({ data, onSelectLine, onOpenEverythingElse, onEdit }: {
  data: BudgetData;
  onSelectLine: (line: BudgetLine) => void;
  onOpenEverythingElse: () => void;
  onEdit: () => void;
}) {
  const paceElapsed = data.pace.current ? data.pace.percent_elapsed : null;
  const groups = groupLines(data.lines);
  const other = data.everything_else;
  const year = data.month.slice(0, 4);

  return (
    <div className="space-y-4">
      <section className="overflow-hidden rounded-xl border bg-card shadow-sm" aria-label="Monthly budgets">
        <ColumnHeader first="Monthly" />
        <ul className="divide-y">
          {groups.map((group) => (
            <li key={group.id}>
              {group.line ? (
                <LineRow line={group.line} paceElapsed={paceElapsed} onSelect={() => onSelectLine(group.line!)} />
              ) : (
                <p className="px-4 pb-0.5 pt-2.5 text-xs font-medium text-muted-foreground">{group.name}</p>
              )}
              {group.children.map((child) => (
                <LineRow key={child.category_id} line={child} paceElapsed={paceElapsed} indent
                         onSelect={() => onSelectLine(child)} />
              ))}
            </li>
          ))}
          <li>
            <EverythingElseRow other={other} paceElapsed={paceElapsed} onOpen={onOpenEverythingElse} onEdit={onEdit} />
          </li>
        </ul>
      </section>

      {data.yearly.lines.length > 0 && (
        <section className="overflow-hidden rounded-xl border bg-card shadow-sm" aria-label="Yearly budgets">
          <ColumnHeader first={`Yearly · spent so far in ${year}`} />
          <ul className="divide-y">
            {data.yearly.lines.map((line) => (
              <li key={line.category_id}>
                <LineRow line={line} paceElapsed={null} onSelect={() => onSelectLine(line)} />
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

function ColumnHeader({ first }: { first: string }) {
  return (
    <div className="flex items-baseline justify-between border-b px-4 py-2 text-xs font-medium text-muted-foreground">
      <span>{first}</span>
      <span>Left</span>
    </div>
  );
}

function LineRow({ line, paceElapsed, indent = false, onSelect }: {
  line: BudgetLine;
  paceElapsed: number | null;
  indent?: boolean;
  onSelect: () => void;
}) {
  const budget = available(line);
  const projectedOver = line.projected != null && line.projected - budget >= 1;
  const rolledUp = line.rolled_up_children;

  return (
    <button
      type="button"
      onClick={onSelect}
      className={cn(
        "group flex w-full items-center gap-3 py-2.5 pr-4 text-left transition-colors hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
        indent ? "pl-8" : "pl-4",
      )}
    >
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5">
          <span className={cn("truncate text-sm", !indent && "font-medium")}>{line.category_name}</span>
          {line.mode === "month_only" && (
            <span className="rounded-full bg-primary/10 px-1.5 py-0.5 text-tiny font-medium text-primary">
              {formatMonthShort(line.set_in)} only
            </span>
          )}
          {line.rollover_amount !== 0 && (
            <span
              className={cn(
                "inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 text-tiny font-medium tabular-nums",
                line.rollover_amount > 0 ? "bg-positive/10 text-positive" : "bg-negative/10 text-negative",
              )}
              title={`Rolled over ${formatCurrency(line.rollover_amount)} from last month`}
            >
              <RotateCcw size={9} />
              {(line.rollover_amount > 0 ? "+" : "") + formatCurrency(line.rollover_amount)}
            </span>
          )}
        </div>
        <div className="mt-1.5 flex items-center gap-3">
          <BudgetProgress percentUsed={line.percent_used} paceElapsed={paceElapsed} className="max-w-[220px] flex-1" />
          <span className="shrink-0 whitespace-nowrap text-xs tabular-nums text-muted-foreground">
            {formatCurrency(line.actual)} of {formatCurrency(budget)}
          </span>
        </div>
        {(projectedOver || rolledUp.length > 0) && (
          <p className="mt-1 truncate text-xs text-muted-foreground">
            {projectedOver && (
              <span className="text-warning">On pace for {formatCurrency(line.projected)}</span>
            )}
            {projectedOver && rolledUp.length > 0 && " · "}
            {rolledUp.length > 0 && (
              <span title={rolledUp.map((c) => `${c.name}: ${formatCurrency(c.actual)}`).join(", ")}>
                includes {rolledUp.map((c) => c.name).join(", ")}
              </span>
            )}
          </p>
        )}
      </div>
      <span className={cn("w-24 shrink-0 text-right text-sm font-medium tabular-nums", moneyColor(line.remaining))}>
        {formatCurrency(line.remaining)}
      </span>
      <ChevronRight size={14} className="shrink-0 text-muted-foreground/50 group-hover:text-muted-foreground" />
    </button>
  );
}

function EverythingElseRow({ other, paceElapsed, onOpen, onEdit }: {
  other: BudgetData["everything_else"];
  paceElapsed: number | null;
  onOpen: () => void;
  onEdit: () => void;
}) {
  const planned = other.planned;
  const percentUsed = planned != null && planned > 0 ? (other.actual / planned) * 100 : other.actual > 0 ? 100 : 0;
  const projectedOver = planned != null && other.projected != null && other.projected - planned >= 1;

  return (
    <div className="flex items-center gap-3 bg-muted/20 py-2.5 pl-4 pr-4">
      <button
        type="button"
        onClick={onOpen}
        className="group flex min-w-0 flex-1 items-center gap-3 rounded text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        title="See this month's transactions"
      >
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium">Everything else</p>
          {planned != null ? (
            <div className="mt-1.5 flex items-center gap-3">
              <BudgetProgress percentUsed={percentUsed} paceElapsed={paceElapsed} className="max-w-[220px] flex-1" />
              <span className="shrink-0 whitespace-nowrap text-xs tabular-nums text-muted-foreground">
                {formatCurrency(other.actual)} of {formatCurrency(planned)}
              </span>
            </div>
          ) : (
            <p className="mt-0.5 text-xs text-muted-foreground">
              <span className="tabular-nums">{formatCurrency(other.actual)}</span> spent in categories without a budget
            </p>
          )}
          {(projectedOver || other.uncategorized > 0) && (
            <p className="mt-1 text-xs text-muted-foreground">
              {projectedOver && <span className="text-warning">On pace for {formatCurrency(other.projected)}</span>}
              {projectedOver && other.uncategorized > 0 && " · "}
              {other.uncategorized > 0 && <>{formatCurrency(other.uncategorized)} uncategorized</>}
            </p>
          )}
        </div>
      </button>
      {other.remaining != null ? (
        <span className={cn("w-24 shrink-0 text-right text-sm font-medium tabular-nums", moneyColor(other.remaining))}>
          {formatCurrency(other.remaining)}
        </span>
      ) : (
        <button
          type="button"
          onClick={onEdit}
          className="w-24 shrink-0 rounded text-right text-xs font-medium text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          Set a budget
        </button>
      )}
      <span className="w-3.5 shrink-0" />
    </div>
  );
}
