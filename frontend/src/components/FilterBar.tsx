import { useEffect, useRef, useState } from "react";
import { Filter, X, BookMarked, Check, SlidersHorizontal, Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import type { SavedView } from "@/api/types";
import { ALL_COLUMNS, CASH_FIELDS } from "./filter-bar/types";
import type { ActiveFilter, DisplayOptions, FieldDef } from "./filter-bar/types";
import { PickerContent, FilterValueDisplay, FilterValueEditor } from "./filter-bar/FilterEditors";
import { DisplayOptionsPanel } from "./filter-bar/DisplayOptionsPanel";

export { ALL_COLUMNS, CASH_FIELDS } from "./filter-bar/types";
export type { ActiveFilter, ColumnKey, DisplayOptions, FieldDef, FieldEditorSpec, GroupByKey, SortDir, SortField, SortOption } from "./filter-bar/types";
export { DisplayOptionsPanel } from "./filter-bar/DisplayOptionsPanel";

// Keep backward-compatible alias

const OP_LABELS: Record<string, string> = {
  equals: "=", not_equals: "≠", greater_than: ">", less_than: "<", contains: "contains",
  matches: "matches", blank: "is empty", present: "is set", in: "is one of",
  month: "in", gte: "on or after", lte: "on or before",
};

let keySeq = 100;

// ── Main component ────────────────────────────────────────────────────────────

interface Props {
  filters: ActiveFilter[];
  matchAll: boolean;
  onChange: (filters: ActiveFilter[]) => void;
  onMatchAllChange: (v: boolean) => void;
  onSave?: () => void;
  savedViews?: SavedView[];
  activeViewId?: string | null;
  onApplyView?: (view: SavedView) => void;
  resultCount?: number;
  isLoading?: boolean;
  searchQuery?: string;
  onSearchChange?: (q: string) => void;
  // Field config — defaults to CASH_FIELDS
  fields?: FieldDef[];
  /** Display-options popover state + callbacks, bundled (see DisplayOptions).
   *  The popover trigger renders only when a columns or group-by callback is
   *  present. */
  display?: DisplayOptions;
}

export function FilterBar({ filters, matchAll, onChange, onMatchAllChange, onSave, savedViews, activeViewId, onApplyView, resultCount, isLoading, searchQuery, onSearchChange, fields = CASH_FIELDS, display }: Props) {
  // The pieces FilterBar reads itself (trigger visibility + active styling);
  // everything else in `display` just forwards to the panel.
  const { columns, onColumnsChange, groupBy = "none", onGroupByChange } = display ?? {};
  const [pickerOpen, setPickerOpen] = useState(false);
  const [plusPickerOpen, setPlusPickerOpen] = useState(false);
  const [hoveredField, setHoveredField] = useState<FieldDef | null>(null);
  const [editingKey, setEditingKey] = useState<number | null>(null);
  const [viewsOpen, setViewsOpen] = useState(false);
  const [displayOpen, setDisplayOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);

  function openFieldPicker() {
    setHoveredField(null);
    setPickerOpen(true);
  }

  function commitFilter(operator: string, value: string) {
    const noValueOp = operator === "blank" || operator === "present";
    if (!hoveredField || (!value && !noValueOp)) return;
    const f: ActiveFilter = { _key: ++keySeq, field: hoveredField.key, operator, value };
    onChange([...filters, f]);
    setPickerOpen(false);
    setPlusPickerOpen(false);
    setHoveredField(null);
  }

  function cancelPicker() {
    setPickerOpen(false);
    setPlusPickerOpen(false);
    setHoveredField(null);
  }

  function removeFilter(key: number) {
    onChange(filters.filter((f) => f._key !== key));
    if (editingKey === key) setEditingKey(null);
  }

  function updateFilter(key: number, patch: Partial<ActiveFilter>) {
    onChange(filters.map((f) => f._key === key ? { ...f, ...patch } : f));
  }

  const hasFilters = filters.length > 0;

  return (
    <div className="flex flex-wrap items-center gap-2">
      {/* Active filter pills — left side */}
      {filters.map((f) => (
        <FilterPill
          key={f._key}
          filter={f}
          fields={fields}
          editing={editingKey === f._key}
          onEdit={() => setEditingKey(editingKey === f._key ? null : f._key)}
          onClose={() => setEditingKey(null)}
          onUpdate={(patch) => updateFilter(f._key, patch)}
          onRemove={() => removeFilter(f._key)}
        />
      ))}

      {/* + button with its own left-anchored Popover */}
      {hasFilters && (
        <Popover
          open={plusPickerOpen}
          onOpenChange={(o) => { if (!o) cancelPicker(); else { setHoveredField(null); setPlusPickerOpen(true); } }}
          align="left"
          trigger={
            <button
              onClick={() => { setHoveredField(null); setPlusPickerOpen((o) => !o); }}
              className="flex h-5 w-5 items-center justify-center rounded-full border text-muted-foreground hover:bg-accent hover:text-foreground transition-colors text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              title="Add filter"
              aria-label="Add filter"
            >
              +
            </button>
          }
        >
          <PickerContent fields={fields} hoveredField={hoveredField} setHoveredField={setHoveredField} onCommit={commitFilter} />
        </Popover>
      )}

      {/* Match ALL / ANY toggle when multiple filters */}
      {filters.length > 1 && (
        <div className="flex items-center gap-1 text-xs text-muted-foreground">
          <span>match</span>
          <button
            onClick={() => onMatchAllChange(!matchAll)}
            className="rounded border px-1.5 py-0.5 font-medium hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            {matchAll ? "ALL" : "ANY"}
          </button>
        </div>
      )}

      {/* Search icon + sliding input + result count */}
      {onSearchChange && (
        <div className="ml-3 flex items-center gap-1.5">
          <button
            onClick={() => {
              setSearchOpen((o) => {
                if (!o) setTimeout(() => searchInputRef.current?.focus(), 0);
                else onSearchChange("");
                return !o;
              });
            }}
            className={cn(
              "shrink-0 rounded p-0.5 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
              searchOpen || searchQuery
                ? "text-primary hover:bg-primary/10"
                : "text-muted-foreground hover:text-foreground"
            )}
            title="Search"
            aria-label="Search"
          >
            <Search size={13} />
          </button>
          <div
            className={cn(
              "overflow-hidden transition-[max-width] duration-200 ease-out",
              searchOpen ? "max-w-40" : "max-w-0"
            )}
          >
            <input
              ref={searchInputRef}
              value={searchQuery ?? ""}
              onChange={(e) => onSearchChange(e.target.value)}
              onBlur={() => { if (!searchQuery) setSearchOpen(false); }}
              onKeyDown={(e) => {
                if (e.key === "Escape") { onSearchChange(""); setSearchOpen(false); }
              }}
              placeholder="Search…"
              aria-label="Search"
              className="w-40 bg-transparent text-xs placeholder:text-muted-foreground focus-visible:outline-none"
            />
          </div>
          {!isLoading && resultCount !== undefined && (
            <span className="whitespace-nowrap text-xs text-muted-foreground">
              {resultCount.toLocaleString()} result{resultCount !== 1 ? "s" : ""}
            </span>
          )}
        </div>
      )}

      {!onSearchChange && !isLoading && resultCount !== undefined && (
        <span className="ml-3 text-xs text-muted-foreground">
          {resultCount.toLocaleString()} result{resultCount !== 1 ? "s" : ""}
        </span>
      )}

      {hasFilters && (
        <button
          onClick={() => { onChange([]); setEditingKey(null); }}
          className="ml-1 rounded text-xs text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          Clear filters
        </button>
      )}

      {/* Right-aligned: Save, views, Filter trigger */}
      <div className="ml-auto flex items-center gap-2">

        {hasFilters && onSave && (
          <Button variant="outline" size="xs" onClick={onSave}>
            Save
          </Button>
        )}

        {savedViews && savedViews.length > 0 && onApplyView && (
          <Popover
            open={viewsOpen}
            onOpenChange={setViewsOpen}
            trigger={
              <button
                onClick={() => setViewsOpen((o) => !o)}
                className={cn(
                  "rounded p-1 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                  activeViewId
                    ? "text-primary hover:bg-primary/10"
                    : "text-muted-foreground hover:bg-accent hover:text-foreground"
                )}
                title="Saved views"
              >
                <BookMarked size={14} />
              </button>
            }
          >
            <ul className="min-w-44 py-1">
              {savedViews.map((view) => (
                <li key={view.id}>
                  <button
                    onClick={() => { onApplyView(view); setViewsOpen(false); }}
                    className={cn(
                      "flex w-full items-center gap-2 px-3 py-2 text-sm transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
                      activeViewId === view.id && "font-medium text-primary"
                    )}
                  >
                    <Check size={13} className={cn("shrink-0", activeViewId === view.id ? "opacity-100" : "opacity-0")} />
                    {view.name}
                  </button>
                </li>
              ))}
            </ul>
          </Popover>
        )}

        {/* Display options */}
        {(onColumnsChange || onGroupByChange) && (
          <Popover
            open={displayOpen}
            onOpenChange={setDisplayOpen}
            trigger={
              <button
                onClick={() => setDisplayOpen((o) => !o)}
                className={cn(
                  "rounded p-1 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                  (groupBy !== "none" || (columns && columns.length < ALL_COLUMNS.length))
                    ? "text-primary hover:bg-primary/10"
                    : "text-muted-foreground hover:bg-accent hover:text-foreground"
                )}
                title="Display options"
              >
                <SlidersHorizontal size={14} />
              </button>
            }
          >
            <DisplayOptionsPanel
              {...display}
              columns={columns ?? [...ALL_COLUMNS]}
              groupBy={groupBy}
            />
          </Popover>
        )}

        <Popover
          open={pickerOpen}
          onOpenChange={(o) => { if (!o) cancelPicker(); }}
          trigger={
            <button
              onClick={openFieldPicker}
              className={cn(
                "rounded p-1 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                hasFilters
                  ? "text-primary hover:bg-primary/10"
                  : "text-muted-foreground hover:bg-accent hover:text-foreground"
              )}
              title="Filter"
            >
              <Filter size={14} />
            </button>
          }
        >
          <PickerContent fields={fields} hoveredField={hoveredField} setHoveredField={setHoveredField} onCommit={commitFilter} />
        </Popover>
      </div>
    </div>
  );
}

// ── Individual filter pill ────────────────────────────────────────────────────

function FilterPill({ filter, fields, editing, onEdit, onClose, onUpdate, onRemove }: {
  filter: ActiveFilter;
  fields: FieldDef[];
  editing: boolean;
  onEdit: () => void;
  onClose: () => void;
  onUpdate: (patch: Partial<ActiveFilter>) => void;
  onRemove: () => void;
}) {
  const fieldDef = fields.find((f) => f.key === filter.field);

  return (
    <Popover
      open={editing}
      onOpenChange={(o) => { if (!o) onClose(); }}
      trigger={
        <div className="flex items-stretch rounded-lg border bg-muted/60 text-xs overflow-hidden">
          <button
            onClick={onEdit}
            className="flex items-center gap-1.5 px-2 py-0.5 hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
          >
            <span className="font-medium">{fieldDef?.label ?? filter.field}</span>
            <span className="text-muted-foreground">{OP_LABELS[filter.operator] ?? filter.operator}</span>
            <FilterValueDisplay filter={filter} fieldDef={fieldDef} />
          </button>
          <button
            onClick={(e) => { e.stopPropagation(); onRemove(); }}
            className="px-1.5 text-muted-foreground hover:bg-accent hover:text-foreground transition-colors border-l focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
            aria-label="Remove filter"
          >
            <X size={11} />
          </button>
        </div>
      }
    >
      <FilterValueEditor filter={filter} fieldDef={fieldDef} onUpdate={onUpdate} onDone={onClose} />
    </Popover>
  );
}

// ── Popover primitive ─────────────────────────────────────────────────────────

function Popover({ open, onOpenChange, trigger, children, align = "right" }: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  trigger: React.ReactNode;
  children: React.ReactNode;
  align?: "left" | "right";
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ top: number; left?: number; right?: number } | null>(null);

  // Recompute fixed position from trigger rect whenever the popover opens.
  useEffect(() => {
    if (!open || !ref.current) { setPos(null); return; }
    const rect = ref.current.getBoundingClientRect();
    const top = rect.bottom + 4;
    if (align === "right") {
      setPos({ top, right: window.innerWidth - rect.right });
    } else {
      setPos({ top, left: rect.left });
    }
  }, [open, align]);

  useEffect(() => {
    if (!open) return;
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.stopImmediatePropagation();
        onOpenChange(false);
      }
    }
    window.addEventListener("keydown", onKeyDown, { capture: true });
    return () => window.removeEventListener("keydown", onKeyDown, { capture: true });
  }, [open, onOpenChange]);

  return (
    <div ref={ref} className="relative">
      {trigger}
      {open && pos && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => onOpenChange(false)} />
          <div
            className="fixed z-50 min-w-44 rounded-lg border bg-card shadow-lg overflow-hidden"
            style={pos}
          >
            {children}
          </div>
        </>
      )}
    </div>
  );
}
