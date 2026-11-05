import { X, ChevronUp, ChevronDown, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { COLUMN_LABELS, FILTER_FIELD_LABELS } from "./types";
import type { ActiveFilter, FilterField, FilterOperator, GroupBy, HoldingColumn, SortDir, SortField } from "./types";

const ALL_COLUMNS: HoldingColumn[] = [
  "ticker", "quantity", "price", "market_value", "cost_basis",
  "unrealized_gl", "unrealized_gl_pct", "est_annual_income", "dividend_yield", "asset_class",
];

const NUMERIC_OPERATORS: { value: FilterOperator; label: string }[] = [
  { value: "gt",      label: ">" },
  { value: "lt",      label: "<" },
  { value: "equals",  label: "=" },
  { value: "present", label: "is set" },
  { value: "blank",   label: "is blank" },
];

const TEXT_OPERATORS: { value: FilterOperator; label: string }[] = [
  { value: "equals",  label: "is" },
  { value: "present", label: "is set" },
  { value: "blank",   label: "is blank" },
];

function isNumericField(f: FilterField): boolean {
  return f !== "asset_class";
}

// Compact toggle chip used by the group-by and column pickers.
const chipClass = (active: boolean) =>
  cn(
    "rounded-md border px-2 py-0.5 text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
    active
      ? "border-foreground/30 bg-accent font-medium"
      : "border-border text-muted-foreground hover:bg-accent",
  );

export function HoldingsOptionsPanel({
  groupBy,
  setGroupBy,
  sortField,
  setSortField,
  sortDir,
  setSortDir,
  visibleCols,
  setVisibleCols,
  filters,
  addFilter,
  updateFilter,
  removeFilter,
}: {
  groupBy: GroupBy;
  setGroupBy: (g: GroupBy) => void;
  sortField: SortField;
  setSortField: (f: SortField) => void;
  sortDir: SortDir;
  setSortDir: React.Dispatch<React.SetStateAction<SortDir>>;
  visibleCols: HoldingColumn[];
  setVisibleCols: React.Dispatch<React.SetStateAction<HoldingColumn[]>>;
  filters: ActiveFilter[];
  addFilter: () => void;
  updateFilter: (id: number, patch: Partial<ActiveFilter>) => void;
  removeFilter: (id: number) => void;
}) {
  return (
    <div className="space-y-4 p-3">
      {/* Group by */}
      <div>
        <p className="mb-1.5 text-tiny font-semibold uppercase tracking-wider text-muted-foreground">Group by</p>
        <div className="flex gap-1.5">
          {(["none", "asset_class"] as GroupBy[]).map((g) => (
            <button
              key={g}
              onClick={() => setGroupBy(g)}
              className={cn(chipClass(groupBy === g), "px-2.5 py-1", groupBy === g && "text-foreground")}
            >
              {g === "none" ? "None" : "Asset Class"}
            </button>
          ))}
        </div>
      </div>

      {/* Sort */}
      <div>
        <p className="mb-1.5 text-tiny font-semibold uppercase tracking-wider text-muted-foreground">Sort</p>
        <div className="flex gap-1.5">
          <Select
            value={sortField}
            onChange={(e) => setSortField(e.target.value as SortField)}
            aria-label="Sort field"
            wrapperClassName="flex-1"
            className="h-7 pl-2 pr-7 text-xs shadow-none"
          >
            {ALL_COLUMNS.map((c) => (
              <option key={c} value={c}>{COLUMN_LABELS[c]}</option>
            ))}
          </Select>
          <Button
            variant="outline"
            size="xs"
            onClick={() => setSortDir((d) => (d === "asc" ? "desc" : "asc"))}
            className="gap-1 px-2 font-normal"
          >
            {sortDir === "asc" ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
            {sortDir === "asc" ? "Asc" : "Desc"}
          </Button>
        </div>
      </div>

      {/* Columns */}
      <div>
        <p className="mb-1.5 text-tiny font-semibold uppercase tracking-wider text-muted-foreground">Columns</p>
        <div className="flex flex-wrap gap-1.5">
          {ALL_COLUMNS.map((col) => {
            const active = visibleCols.includes(col);
            return (
              <button
                key={col}
                onClick={() => {
                  setVisibleCols((prev) =>
                    active && prev.length > 1
                      ? prev.filter((c) => c !== col)
                      : active ? prev : [...prev, col]
                  );
                }}
                className={chipClass(active)}
              >
                {COLUMN_LABELS[col]}
              </button>
            );
          })}
        </div>
      </div>

      {/* Filters */}
      <div>
        <p className="mb-1.5 text-tiny font-semibold uppercase tracking-wider text-muted-foreground">Filters</p>
        <div className="space-y-1.5">
          {filters.map((f) => {
            const ops = isNumericField(f.field) ? NUMERIC_OPERATORS : TEXT_OPERATORS;
            const needsValue = f.operator !== "blank" && f.operator !== "present";
            return (
              <div key={f.id} className="flex items-center gap-1">
                <Select
                  value={f.field}
                  onChange={(e) => {
                    const field = e.target.value as FilterField;
                    updateFilter(f.id, { field, operator: isNumericField(field) ? "gt" : "equals", value: "" });
                  }}
                  aria-label="Filter field"
                  wrapperClassName="w-28"
                  className="h-7 pl-1.5 pr-6 text-xs shadow-none"
                >
                  {(Object.keys(FILTER_FIELD_LABELS) as FilterField[]).map((k) => (
                    <option key={k} value={k}>{FILTER_FIELD_LABELS[k]}</option>
                  ))}
                </Select>
                <Select
                  value={f.operator}
                  onChange={(e) => updateFilter(f.id, { operator: e.target.value as FilterOperator })}
                  aria-label="Filter operator"
                  wrapperClassName="w-20"
                  className="h-7 pl-1.5 pr-6 text-xs shadow-none"
                >
                  {ops.map((o) => (
                    <option key={o.value} value={o.value}>{o.label}</option>
                  ))}
                </Select>
                {needsValue && (
                  <Input
                    value={f.value}
                    onChange={(e) => updateFilter(f.id, { value: e.target.value })}
                    placeholder={isNumericField(f.field) ? "0" : "value"}
                    aria-label="Filter value"
                    className={cn("h-7 w-16 px-1.5 text-xs shadow-none", isNumericField(f.field) && "tabular-nums")}
                  />
                )}
                <button
                  onClick={() => removeFilter(f.id)}
                  aria-label="Remove filter"
                  className="ml-auto rounded text-muted-foreground hover:text-destructive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  <X size={12} />
                </button>
              </div>
            );
          })}
          <Button
            variant="ghost"
            size="xs"
            onClick={addFilter}
            className="gap-1 px-1.5 font-normal text-muted-foreground hover:text-foreground"
          >
            <Plus size={12} />
            Add filter
          </Button>
        </div>
      </div>
    </div>
  );
}
