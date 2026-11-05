import { cn } from "@/lib/utils";
import { Select } from "@/components/ui/select";
import { Tabs } from "@/components/ui/tabs";
import { ALL_COLUMNS } from "./types";
import type { ColumnKey, GroupByKey, SortField, SortDir, SortOption } from "./types";

const COLUMN_LABELS: Record<ColumnKey, string> = {
  date: "Date", description: "Description", merchant: "Merchant",
  category: "Category", account: "Account", amount: "Amount",
  type: "Type", tags: "Tags", note: "Note",
};

const SORT_FIELDS: { key: SortField; label: string }[] = [
  { key: "date",        label: "Date"        },
  { key: "amount",      label: "Amount"      },
  { key: "merchant",    label: "Merchant"    },
  { key: "category",    label: "Category"    },
  { key: "description", label: "Description" },
];

const GROUP_OPTIONS: { key: GroupByKey; label: string }[] = [
  { key: "none",     label: "None"     },
  { key: "month",    label: "Month"    },
  { key: "merchant", label: "Merchant" },
  { key: "category", label: "Category" },
];

// ── Display options panel ─────────────────────────────────────────────────────

function SortRow({ label, value, sortFields, onField, onDir, onClear }: {
  label: string;
  value: SortOption | null;
  sortFields: { key: string; label: string }[];
  onField: (f: string | null) => void;
  onDir: (d: SortDir) => void;
  onClear?: () => void;
}) {
  return (
    <div className="flex items-center justify-between gap-2 text-sm">
      <span className="shrink-0 text-xs text-muted-foreground">{label}</span>
      <div className="flex items-center gap-1">
        <Select
          value={value?.field ?? ""}
          onChange={(e) => onField(e.target.value || null)}
          aria-label={`${label} sort field`}
          className="h-7 pl-1.5 pr-7 text-xs"
        >
          {label === "Secondary" && <option value="">None</option>}
          {sortFields.map((f) => (
            <option key={f.key} value={f.key}>{f.label}</option>
          ))}
        </Select>
        {value && (
          <button
            onClick={() => onDir(value.dir === "asc" ? "desc" : "asc")}
            className="rounded border px-1.5 py-0.5 text-xs text-muted-foreground hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            title={value.dir === "asc" ? "Ascending" : "Descending"}
            aria-label={value.dir === "asc" ? "Ascending" : "Descending"}
          >
            {value.dir === "asc" ? "↑" : "↓"}
          </button>
        )}
        {onClear && value && (
          <button
            onClick={onClear}
            className="rounded border px-1.5 py-0.5 text-xs text-muted-foreground hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            title="Clear"
            aria-label="Clear"
          >
            ×
          </button>
        )}
      </div>
    </div>
  );
}

export function DisplayOptionsPanel({ columns, onColumnsChange, groupBy, onGroupByChange, sortFields: sortFieldsProp, groupOptions: groupOptionsProp, primarySort, onPrimarySort, secondarySort, onSecondarySort, showTransfers, onShowTransfersChange, className }: {
  columns: ColumnKey[];
  onColumnsChange?: (cols: ColumnKey[]) => void;
  groupBy: GroupByKey;
  onGroupByChange?: (g: GroupByKey) => void;
  sortFields?: { key: string; label: string }[];
  groupOptions?: { key: string; label: string }[];
  primarySort?: SortOption;
  onPrimarySort?: (s: SortOption) => void;
  secondarySort?: SortOption | null;
  onSecondarySort?: (s: SortOption | null) => void;
  showTransfers?: boolean;
  onShowTransfersChange?: (v: boolean) => void;
  className?: string;
}) {
  const effectiveSortFields = sortFieldsProp ?? SORT_FIELDS;
  const effectiveGroupOptions = groupOptionsProp ?? GROUP_OPTIONS;

  function toggleCol(col: ColumnKey) {
    if (!onColumnsChange) return;
    const next = columns.includes(col)
      ? columns.filter((c) => c !== col)
      : [...columns, col];
    // always keep at least one column
    if (next.length > 0) onColumnsChange(next);
  }

  return (
    <div className={cn("w-64 space-y-4 p-4", className)}>
      {/* Grouping */}
      {onGroupByChange && (
        <div>
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Group by</p>
          <Tabs
            size="sm"
            value={groupBy}
            onChange={(g) => onGroupByChange(g)}
            options={effectiveGroupOptions.map((opt) => ({ value: opt.key, label: opt.label }))}
            className="flex-wrap"
          />
        </div>
      )}

      {/* Sort */}
      {onPrimarySort && primarySort && (
        <div className="space-y-2">
          <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Sort</p>
          <SortRow
            label="Primary"
            value={primarySort}
            sortFields={effectiveSortFields}
            onField={(f) => f && onPrimarySort({ ...primarySort, field: f })}
            onDir={(d) => onPrimarySort({ ...primarySort, dir: d })}
          />
          {onSecondarySort && (
            <SortRow
              label="Secondary"
              value={secondarySort ?? null}
              sortFields={effectiveSortFields}
              onField={(f) => onSecondarySort(f ? { field: f, dir: "asc" } : null)}
              onDir={(d) => secondarySort && onSecondarySort({ ...secondarySort, dir: d })}
              onClear={() => onSecondarySort(null)}
            />
          )}
        </div>
      )}

      {/* Columns */}
      {onColumnsChange && (
        <div>
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Columns</p>
          <div className="flex flex-wrap gap-1.5">
            {ALL_COLUMNS.map((col) => {
              const active = columns.includes(col);
              return (
                <button
                  key={col}
                  onClick={() => toggleCol(col)}
                  aria-pressed={active}
                  className={cn(
                    "rounded-full border px-3 py-1 text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                    active
                      ? "border-foreground/30 font-medium text-foreground"
                      : "border-border text-muted-foreground hover:bg-accent"
                  )}
                >
                  {COLUMN_LABELS[col]}
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* Transfers toggle */}
      {onShowTransfersChange && (
        <button
          onClick={() => onShowTransfersChange(!showTransfers)}
          role="switch"
          aria-checked={showTransfers}
          className="flex items-center gap-2 rounded text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          <div className={cn(
            "relative h-4 w-7 shrink-0 rounded-full transition-colors",
            showTransfers ? "bg-primary" : "bg-input"
          )}>
            {/* Knob is deliberately bg-white (not a semantic token): it must stay
                light on top of both the bg-primary and bg-input track colors. */}
            <div className={cn(
              "absolute top-0.5 h-3 w-3 rounded-full bg-white shadow transition-transform",
              showTransfers ? "translate-x-3.5" : "translate-x-0.5"
            )} />
          </div>
          <span className="text-xs text-muted-foreground">Show transfers</span>
        </button>
      )}
    </div>
  );
}
