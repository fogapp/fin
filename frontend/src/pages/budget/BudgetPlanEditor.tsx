import { useMemo } from "react";
import { Trash2 } from "lucide-react";
import { cn, formatCurrency, formatDate, formatDollars } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { useConfirm } from "@/components/ui/confirm";
import { SegmentedToggle } from "@/components/charts";
import type {
  BudgetData, BudgetLine, BudgetLineMode, BudgetPeriodKind, BudgetSuggestion, BudgetSuggestions, CategorySummary,
} from "@/api/types";
import { monthLabel } from "@/lib/monthLabel";
import { AmountInput } from "./AmountInput";
import { orderedLines } from "./budgetGroups";
import { formatMonthShort } from "./budgetMonth";

export interface LineChange {
  planned?: number;
  rollover?: boolean;
  period?: BudgetPeriodKind;
}

/** How many unbudgeted categories the add-picker suggests first. */
const SUGGESTED_ADDS = 8;

/**
 * Plan mode: every amount is an input, next to what the category typically
 * costs — the median month, which a one-off purchase doesn't skew, with the
 * unusual charges it leaves out named. Changes apply from this month on (the
 * plan carries forward) or to this month only.
 */
export function BudgetPlanEditor({
  data, suggestions, categories, applyMode, onApplyModeChange, onSetLine, onStopLine, onSetPeriod,
}: {
  data: BudgetData;
  suggestions: BudgetSuggestions | undefined;
  categories: CategorySummary[];
  applyMode: BudgetLineMode;
  onApplyModeChange: (mode: BudgetLineMode) => void;
  onSetLine: (categoryId: string, change: LineChange) => void;
  onStopLine: (line: BudgetLine) => void;
  onSetPeriod: (body: { income_planned?: number | null; other_planned?: number | null }) => void;
}) {
  const byCategory = useMemo(
    () => new Map((suggestions?.categories ?? []).map((s) => [s.category_id, s])),
    [suggestions],
  );
  const monthly = orderedLines(data.lines);
  const yearly = data.yearly.lines;
  const budgetedIds = new Set([...monthly, ...yearly].map((l) => l.category_id));
  const monthName = formatMonthShort(data.month);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card px-4 py-3 shadow-sm">
        <p className="text-sm text-muted-foreground">
          Budgets carry forward to later months until you change them.
        </p>
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <span>Changes apply</span>
          <SegmentedToggle
            label="Changes apply"
            options={[
              { value: "ongoing", label: `From ${monthName} on` },
              { value: "month_only", label: `${monthName} only` },
            ]}
            value={applyMode}
            onChange={onApplyModeChange}
          />
        </div>
      </div>

      <section className="overflow-hidden rounded-xl border bg-card shadow-sm" aria-label="Monthly budget amounts">
        <SectionHeader title="Monthly" />
        {monthly.length === 0 && (
          <p className="px-4 py-3 text-sm text-muted-foreground">No categories yet — add the few you want to keep an eye on.</p>
        )}
        <ul className="divide-y">
          {monthly.map((line) => (
            <PlanRow key={line.category_id} line={line} suggestion={byCategory.get(line.category_id)}
                     loading={!suggestions} onSetLine={onSetLine} onStopLine={onStopLine} />
          ))}
          <EverythingElseRow data={data} suggestions={suggestions} onSetPeriod={onSetPeriod} />
        </ul>
        <AddCategory
          categories={categories}
          budgetedIds={budgetedIds}
          suggestions={suggestions}
          onAdd={(id) => onSetLine(id, { planned: byCategory.get(id)?.suggested ?? 0 })}
        />
      </section>

      {yearly.length > 0 && (
        <section className="overflow-hidden rounded-xl border bg-card shadow-sm" aria-label="Yearly budget amounts">
          <SectionHeader title="Yearly" hint="For costs that don't land every month — insurance, gifts, travel." />
          <ul className="divide-y">
            {yearly.map((line) => (
              <PlanRow key={line.category_id} line={line} suggestion={byCategory.get(line.category_id)}
                       loading={!suggestions} onSetLine={onSetLine} onStopLine={onStopLine} />
            ))}
          </ul>
        </section>
      )}

      <Totals data={data} onSetPeriod={onSetPeriod} />
    </div>
  );
}

function SectionHeader({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="border-b px-4 py-2">
      <div className="flex items-baseline justify-between text-xs font-medium text-muted-foreground">
        <span>{title}</span>
        <span>Budget</span>
      </div>
      {hint && <p className="mt-0.5 text-xs text-muted-foreground/80">{hint}</p>}
    </div>
  );
}

function PlanRow({ line, suggestion, loading, onSetLine, onStopLine }: {
  line: BudgetLine;
  suggestion: BudgetSuggestion | undefined;
  loading: boolean;
  onSetLine: (categoryId: string, change: LineChange) => void;
  onStopLine: (line: BudgetLine) => void;
}) {
  const confirm = useConfirm();
  const yearly = line.period === "yearly";
  const target = suggestion ? (yearly ? roundUp5(suggestion.year_total) : suggestion.suggested) : null;
  const offerSuggestion = target != null && target > 0 && Math.abs(target - line.planned) >= 1;

  return (
    <li className={cn("flex flex-wrap items-center gap-x-3 gap-y-2 py-3 pr-4", line.parent_id ? "pl-8" : "pl-4")}>
      <div className="min-w-0 flex-1 basis-56">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className={cn("text-sm", !line.parent_id && "font-medium")}>{line.category_name}</span>
          {line.parent_name && <span className="text-xs text-muted-foreground">in {line.parent_name}</span>}
          {line.mode === "month_only" && (
            <span className="rounded-full bg-primary/10 px-1.5 py-0.5 text-tiny font-medium text-primary">
              {formatMonthShort(line.set_in)} only
            </span>
          )}
        </div>
        {loading ? <Skeleton className="mt-1 h-4 w-48 rounded" /> : <TypicalSpend suggestion={suggestion} yearly={yearly} />}
      </div>

      <div className="flex shrink-0 items-center gap-2">
        {offerSuggestion && (
          <Button variant="ghost" size="xs" className="text-muted-foreground"
                  onClick={() => onSetLine(line.category_id, { planned: target })}
                  title={yearly ? "Use the last 12 months' total" : "Use the typical month"}>
            Use {formatDollars(target)}
          </Button>
        )}
        <AmountInput
          value={line.planned}
          label={`Budget for ${line.category_name}`}
          onCommit={(v) => onSetLine(line.category_id, { planned: v ?? 0 })}
          className="w-28"
        />
        <Select
          aria-label={`How often for ${line.category_name}`}
          value={line.period}
          onChange={(e) => {
            const period = e.target.value as BudgetPeriodKind;
            // Keep the amount equivalent: $100/mo becomes $1,200/yr and back.
            const planned = period === "yearly" ? line.planned * 12 : Math.round(line.planned / 12);
            onSetLine(line.category_id, { period, planned });
          }}
          className="h-8 text-xs"
          wrapperClassName="w-[6.5rem]"
        >
          <option value="monthly">per month</option>
          <option value="yearly">per year</option>
        </Select>
        <button
          type="button"
          onClick={async () => {
            if (await confirm({
              title: `Stop budgeting ${line.category_name}?`,
              description: "Its spending moves to Everything else from this month on. Earlier months keep their budget.",
              confirmLabel: "Stop budgeting",
              destructive: true,
            })) onStopLine(line);
          }}
          className="rounded p-1.5 text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          aria-label={`Stop budgeting ${line.category_name}`}
          title="Stop budgeting this category"
        >
          <Trash2 size={14} />
        </button>
      </div>
    </li>
  );
}

/** "Typically $305/mo ▂▃▂█▂▂ · not counting Design firm $28,970 (Jun 29)". */
function TypicalSpend({ suggestion, yearly }: { suggestion: BudgetSuggestion | undefined; yearly: boolean }) {
  if (!suggestion) return <p className="mt-0.5 text-xs text-muted-foreground">No spending in the last year</p>;

  const unusual = suggestion.unusual[0];
  return (
    <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted-foreground">
      <span className="tabular-nums">
        {yearly
          ? <>{formatDollars(suggestion.year_total)} in the last 12 months</>
          : <>Typically {formatDollars(suggestion.typical)}/mo</>}
      </span>
      <Sparkline values={suggestion.history.map((h) => h.actual)} />
      {!yearly && unusual && (
        <span
          className="truncate"
          title={suggestion.unusual.map((u) => `${u.description ?? "Charge"}: ${formatCurrency(u.amount)} on ${formatDate(u.transaction_date)}`).join("\n")}
        >
          · not counting {unusual.description ?? "a charge"} {formatDollars(unusual.amount)}
          {suggestion.unusual.length > 1 && ` +${suggestion.unusual.length - 1} more`}
        </span>
      )}
    </div>
  );
}

function Sparkline({ values }: { values: number[] }) {
  const max = Math.max(...values, 0);
  if (max <= 0) return null;
  return (
    <span className="inline-flex h-3.5 items-end gap-px" aria-hidden>
      {values.map((v, i) => (
        <span key={i} className="w-1 rounded-sm bg-muted-foreground/40"
              style={{ height: `${Math.max((v / max) * 100, v > 0 ? 12 : 4)}%` }} />
      ))}
    </span>
  );
}

function EverythingElseRow({ data, suggestions, onSetPeriod }: {
  data: BudgetData;
  suggestions: BudgetSuggestions | undefined;
  onSetPeriod: (body: { other_planned: number | null }) => void;
}) {
  const typical = suggestions?.everything_else;
  const planned = data.everything_else.planned;
  const offer = typical && typical.suggested > 0 && (planned == null || Math.abs(typical.suggested - planned) >= 1);

  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-2 bg-muted/20 py-3 pl-4 pr-4">
      <div className="min-w-0 flex-1 basis-56">
        <p className="text-sm font-medium">Everything else</p>
        <p className="mt-0.5 text-xs text-muted-foreground">
          One amount for all the categories not listed
          {typical && <> · typically <span className="tabular-nums">{formatDollars(typical.typical)}</span>/mo</>}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {offer && (
          <Button variant="ghost" size="xs" className="text-muted-foreground"
                  onClick={() => onSetPeriod({ other_planned: typical.suggested })}>
            Use {formatDollars(typical.suggested)}
          </Button>
        )}
        <AmountInput
          value={planned}
          allowEmpty
          placeholder="No budget"
          label="Budget for everything else"
          onCommit={(v) => onSetPeriod({ other_planned: v })}
          className="w-28"
        />
        <span className="w-[6.5rem] text-xs text-muted-foreground">per month</span>
        <span className="w-[1.625rem]" />
      </div>
    </li>
  );
}

function AddCategory({ categories, budgetedIds, suggestions, onAdd }: {
  categories: CategorySummary[];
  budgetedIds: Set<string>;
  suggestions: BudgetSuggestions | undefined;
  onAdd: (categoryId: string) => void;
}) {
  const suggested = (suggestions?.categories ?? [])
    .filter((s) => !budgetedIds.has(s.category_id) && s.typical > 0)
    .slice(0, SUGGESTED_ADDS);
  const suggestedIds = new Set(suggested.map((s) => s.category_id));
  const roots = categories.filter((c) => c.parent_id === null);
  const rest = roots
    .map((root) => ({
      root,
      options: [root, ...categories.filter((c) => c.parent_id === root.id)]
        .filter((c) => !budgetedIds.has(c.id) && !suggestedIds.has(c.id)),
    }))
    .filter((g) => g.options.length > 0);

  if (suggested.length === 0 && rest.length === 0) return null;

  return (
    <div className="border-t px-4 py-2.5">
      <Select
        value=""
        aria-label="Add a category"
        onChange={(e) => { if (e.target.value) onAdd(e.target.value); }}
        className="h-8 cursor-pointer text-xs text-muted-foreground"
        wrapperClassName="max-w-sm"
      >
        <option value="">+ Add a category…</option>
        {suggested.length > 0 && (
          <optgroup label="Biggest spending without a budget">
            {suggested.map((s) => (
              <option key={s.category_id} value={s.category_id}>
                {s.parent_name ? `${s.parent_name} › ` : ""}{s.category_name} — typically {formatDollars(s.typical)}/mo
              </option>
            ))}
          </optgroup>
        )}
        {rest.map(({ root, options }) => (
          <optgroup key={root.id} label={root.name}>
            {options.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </optgroup>
        ))}
      </Select>
    </div>
  );
}

function Totals({ data, onSetPeriod }: {
  data: BudgetData;
  onSetPeriod: (body: { income_planned: number | null }) => void;
}) {
  const setAside = data.yearly.set_aside;
  const left = data.left_to_plan;

  return (
    <section className="space-y-3 rounded-xl border bg-card p-4 shadow-sm" aria-label="Budget totals">
      <div className="flex flex-wrap items-baseline justify-between gap-2 text-sm">
        <span className="text-muted-foreground">Monthly budget for {monthLabel(data.month)}</span>
        <span className="font-semibold tabular-nums">
          {formatCurrency(data.planned)}
          {setAside > 0 && (
            <span className="ml-1 font-normal text-muted-foreground">+ {formatCurrency(setAside)} set aside for yearly</span>
          )}
        </span>
      </div>
      <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
        <div>
          <p className="text-muted-foreground">Expected income <span className="text-xs">(optional)</span></p>
          {data.income.suggestion != null && (
            <p className="text-xs text-muted-foreground">Recent months averaged {formatDollars(data.income.suggestion)}</p>
          )}
        </div>
        <AmountInput
          value={data.income.planned}
          allowEmpty
          placeholder="Not set"
          label="Expected income"
          onCommit={(v) => onSetPeriod({ income_planned: v })}
          className="w-32"
        />
      </div>
      {left != null && (
        <p className={cn(
          "rounded-lg px-3 py-2 text-sm font-medium",
          Math.abs(left) < 1 ? "bg-positive/10 text-positive" : left > 0 ? "bg-muted text-foreground" : "bg-negative/10 text-negative",
        )}>
          {Math.abs(left) < 1
            ? "Every dollar of income has a job"
            : left > 0
              ? `${formatCurrency(left)} of income not budgeted — savings, or room to plan`
              : `Budget exceeds expected income by ${formatCurrency(-left)}`}
        </p>
      )}
    </section>
  );
}

function roundUp5(n: number): number {
  return Math.ceil(n / 5) * 5;
}
