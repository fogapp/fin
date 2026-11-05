export interface ActiveFilter {
  _key: number;
  field: string;
  operator: string;
  value: string;
}

export type GroupByKey = string;

export const ALL_COLUMNS = ["date", "description", "merchant", "category", "account", "amount", "type", "tags", "note"] as const;
export type ColumnKey = typeof ALL_COLUMNS[number];

/** The cash table's sort keys. Sort options are deliberately keyed by plain
 *  string, not this union: each table brings its own `sortFields` list (the
 *  investment table sorts by trade_date / account_name / security_ticker…)
 *  and the panel just round-trips whatever keys it was given. */
export type SortField = "date" | "amount" | "merchant" | "category" | "description";
export type SortDir   = "asc" | "desc";
export interface SortOption { field: string; dir: SortDir }

/** Everything the Display-options popover works with — column visibility,
 *  grouping, primary/secondary sort, the transfers toggle — as one prop
 *  bundle. FilterBar takes it as a single `display` object and forwards it to
 *  DisplayOptionsPanel; a concern is shown only when its callback is given. */
export interface DisplayOptions {
  columns?: ColumnKey[];
  onColumnsChange?: (cols: ColumnKey[]) => void;
  groupBy?: GroupByKey;
  onGroupByChange?: (g: GroupByKey) => void;
  /** Table-specific option lists; defaults are the cash table's. */
  sortFields?: { key: string; label: string }[];
  groupOptions?: { key: string; label: string }[];
  primarySort?: SortOption;
  onPrimarySort?: (s: SortOption) => void;
  secondarySort?: SortOption | null;
  onSecondarySort?: (s: SortOption | null) => void;
  showTransfers?: boolean;
  onShowTransfersChange?: (v: boolean) => void;
}

// ── Field editor discriminated union ─────────────────────────────────────────

export type FieldEditorSpec =
  | { type: "merchant" }
  | { type: "category" }
  | { type: "account" }
  | { type: "date" }
  | { type: "amount" }
  | { type: "select"; options: { value: string; label: string }[] }
  | { type: "text"; placeholder?: string };

export interface FieldDef {
  key: string;
  label: string;
  defaultOperator: string;
  defaultValue: string;
  editor: FieldEditorSpec;
}

export const CASH_FIELDS: FieldDef[] = [
  { key: "merchant_id",       label: "Merchant",     defaultOperator: "equals",        defaultValue: "", editor: { type: "merchant" } },
  { key: "category_id",       label: "Category",     defaultOperator: "equals",        defaultValue: "", editor: { type: "category" } },
  { key: "account_id",        label: "Account",      defaultOperator: "equals",        defaultValue: "", editor: { type: "account" } },
  { key: "transaction_date",  label: "Date",         defaultOperator: "month",         defaultValue: "", editor: { type: "date" } },
  { key: "source",            label: "Source",       defaultOperator: "equals",        defaultValue: "credit_card", editor: { type: "select", options: [{ value: "credit_card", label: "Credit card" }, { value: "bank", label: "Bank" }] } },
  { key: "transaction_type",  label: "Type",         defaultOperator: "equals",        defaultValue: "Sale", editor: { type: "select", options: ["Sale", "Return", "Payment", "Debit", "Credit", "Account Transfer"].map((t) => ({ value: t, label: t })) } },
  { key: "amount",            label: "Amount",       defaultOperator: "greater_than",  defaultValue: "", editor: { type: "amount" } },
  { key: "description",       label: "Description",  defaultOperator: "contains",      defaultValue: "", editor: { type: "text", placeholder: "Enter text…" } },
];
