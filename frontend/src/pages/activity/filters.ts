// ── Timeline filter definitions ───────────────────────────────────────────────
// Shared between the filter chips and the health-strip tiles/chips that apply
// the same filters.

export interface ActivityFilter {
  key: string;
  label: string;
  source?: string;
  severity?: string;
}

/** The filters rendered as chips above the timeline. */
export const TIMELINE_FILTERS: ActivityFilter[] = [
  { key: "all", label: "All" },
  { key: "syncs", label: "Syncs", source: "plaid_sync,coinbase_sync,market_prices,crypto_prices" },
  { key: "imports", label: "Imports", source: "import" },
  { key: "workflows", label: "Workflows", source: "workflow" },
  { key: "system", label: "System", source: "transfer_detection,recurring_detection,merchant_rules,system_audit" },
  { key: "errors", label: "Errors", severity: "error" },
];

/** Filters only reachable from health-strip tiles, not rendered as chips. */
export const TILE_FILTERS: ActivityFilter[] = [
  { key: "workflow_failures", label: "Workflow failures", source: "workflow", severity: "error" },
];

export const ALL_FILTERS: ActivityFilter[] = [...TIMELINE_FILTERS, ...TILE_FILTERS];

/** The chip filter that covers a given activity source, if any. */
export function filterKeyForSource(source: string): string | null {
  return TIMELINE_FILTERS.find((f) => f.source?.split(",").includes(source))?.key ?? null;
}
