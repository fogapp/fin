// ── Public types ─────────────────────────────────────────────────────────────

export interface HoldingRow {
  id: string;
  /** The security this row rolls up to — the key labels are stored against. */
  security_id: string;
  ticker: string | null;
  name: string | null;
  cusip: string | null;
  /** Household-assigned display name; wins over ticker and name when set. */
  label: string | null;
  quantity: number;
  price: number;
  market_value: number;
  cost_basis: number | null;
  unrealized_gl: number;
  unrealized_gl_pct: number;
  asset_class: string | null;
  est_annual_income: number | null;
  dividend_yield: number | null;
  as_of_date: string | null;
}

/** The three identities every security-level row carries, in preference order. */
export interface LabelledSecurity {
  label: string | null;
  ticker: string | null;
  name: string | null;
}

/** Label wins, then ticker, then the custodian description. */
export function holdingDisplayName(h: LabelledSecurity): string | null {
  return h.label?.trim() || h.ticker || h.name || null;
}

/** The secondary line: whatever identity the primary line didn't already use. */
export function holdingSubtitle(h: LabelledSecurity): string | null {
  const primary = holdingDisplayName(h);
  if (h.label?.trim()) return [h.ticker, h.name].filter(Boolean).join(" · ") || null;
  return h.name && h.name !== primary ? h.name : null;
}

export type HoldingColumn =
  | "ticker"
  | "quantity"
  | "price"
  | "market_value"
  | "cost_basis"
  | "unrealized_gl"
  | "unrealized_gl_pct"
  | "est_annual_income"
  | "dividend_yield"
  | "asset_class";

// ── Constants ─────────────────────────────────────────────────────────────────

export const COLUMN_LABELS: Record<HoldingColumn, string> = {
  ticker:            "Ticker",
  quantity:          "Quantity",
  price:             "Price",
  market_value:      "Market Value",
  cost_basis:        "Cost Basis",
  unrealized_gl:     "Unrealized G/L",
  unrealized_gl_pct: "G/L %",
  est_annual_income: "Est. Annual Income",
  dividend_yield:    "Yield",
  asset_class:       "Asset Class",
};

export type SortField = HoldingColumn;
export type SortDir = "asc" | "desc";
export type GroupBy = "none" | "asset_class";

export type FilterField = "market_value" | "unrealized_gl" | "unrealized_gl_pct" | "quantity" | "asset_class";
export type FilterOperator = "gt" | "lt" | "equals" | "blank" | "present";

export interface ActiveFilter {
  id: number;
  field: FilterField;
  operator: FilterOperator;
  value: string;
}

export const FILTER_FIELD_LABELS: Record<FilterField, string> = {
  market_value:      "Market Value",
  unrealized_gl:     "Unrealized G/L",
  unrealized_gl_pct: "G/L %",
  quantity:          "Quantity",
  asset_class:       "Asset Class",
};
