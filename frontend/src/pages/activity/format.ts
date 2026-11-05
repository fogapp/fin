// ── Activity formatting helpers ───────────────────────────────────────────────

const SOURCE_LABELS: Record<string, string> = {
  plaid_sync: "Plaid",
  coinbase_sync: "Coinbase",
  market_prices: "Market prices",
  crypto_prices: "Crypto prices",
  import: "Import",
  transfer_detection: "Transfers",
  recurring_detection: "Recurring",
  merchant_rules: "Merchant rules",
  system_audit: "Audit",
  workflow: "Workflow",
  api: "API",
  job: "Job",
};

export function sourceLabel(source: string) {
  return SOURCE_LABELS[source] ?? source.replace(/_/g, " ");
}

export function formatDuration(ms: number) {
  if (ms < 1000) return `${Math.round(ms)}ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  const m = Math.floor(ms / 60_000);
  const s = Math.round((ms % 60_000) / 1000);
  return s > 0 ? `${m}m ${s}s` : `${m}m`;
}
