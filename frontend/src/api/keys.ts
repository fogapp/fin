import type { QueryClient, QueryKey } from "@tanstack/react-query";

/**
 * Query-key roots. Every query in `queries` builds its key from one of these,
 * and every cache refresh names one — so a typo'd or orphaned key is a type
 * error instead of an invalidation that silently matches nothing. Scoped keys
 * (a detail, a date window) come from the query factory itself:
 * `queries.loan(id).queryKey`.
 */
export const keys = {
  about: ["about"],
  accountBalanceSnapshots: ["account_balance_snapshots"],
  accounts: ["accounts"],
  activity: ["activity"],
  alchemyConfiguration: ["alchemy_configuration"],
  alchemyWallets: ["alchemy_wallets"],
  alphaVantageConfiguration: ["alpha_vantage_configuration"],
  apiTokens: ["api_tokens"],
  backups: ["backups"],
  benchmark: ["benchmark"],
  benchmarks: ["benchmarks"],
  brokers: ["brokers"],
  budget: ["budget"],
  buys: ["buys"],
  cashTransactions: ["cash_transactions"],
  cashflow: ["cashflow"],
  categories: ["categories"],
  coinMarketCapConfiguration: ["coin_market_cap_configuration"],
  coinbaseAccounts: ["coinbase_accounts"],
  coinbaseConfiguration: ["coinbase_configuration"],
  costBasis: ["cost_basis"],
  crypto: ["crypto"],
  dashboard: ["dashboard"],
  dividends: ["dividends"],
  equity: ["equity"],
  fogConnection: ["fog_connection"],
  householdMembers: ["household_memberships"],
  households: ["households"],
  instanceSettings: ["instance_settings"],
  investmentLots: ["investment_lots"],
  investmentTransactions: ["investment_transactions"],
  importSpreadsheetFormat: ["import_spreadsheet_format"],
  invites: ["invites"],
  issues: ["issues"],
  loans: ["loans"],
  marketSummary: ["market_summary"],
  me: ["me"],
  merchants: ["merchants"],
  netWorth: ["net_worth"],
  notifications: ["notifications"],
  officeConfiguration: ["office_configuration"],
  officeSheetExports: ["office_sheet_exports"],
  officeSpreadsheetPreview: ["office_spreadsheet_preview"],
  officeSpreadsheets: ["office_spreadsheets"],
  plaidConfiguration: ["plaid_configuration"],
  plaidItems: ["plaid_items"],
  plaidLinkToken: ["plaid_link_token"],
  portfolio: ["portfolio"],
  preferences: ["preferences"],
  realEstateProperties: ["real_estate_properties"],
  rentcastConfiguration: ["rentcast_configuration"],
  review: ["review"],
  savedReports: ["saved_reports"],
  savedViews: ["saved_views"],
  search: ["search"],
  securities: ["securities"],
  securityConversions: ["security_conversions"],
  securitySearch: ["security_search"],
  sells: ["sells"],
  stats: ["stats"],
  subscriptions: ["subscriptions"],
  systemHealth: ["system_health"],
  tags: ["tags"],
  taxProfile: ["tax_profile"],
  taxReport: ["tax_report"],
  tiingoConfiguration: ["tiingo_configuration"],
  transferSearch: ["transfer_search"],
  // The detail page's per-row context — derived from many rows, so edits mark
  // it stale with the other transaction aggregates.
  transactionContext: ["transaction_context"],
  transfers: ["transfers"],
  webauthnCredentials: ["webauthn_credentials"],
  workflowCatalog: ["workflow_catalog"],
  workflowRuns: ["workflow_runs"],
  workflows: ["workflows"],
} as const satisfies Record<string, readonly [string]>;

/**
 * Mark every query under each key stale (refetching the active ones). Resolves
 * once those refetches settle, so a mutation's onSuccess can return it to stay
 * pending until the UI shows fresh data.
 */
export function invalidate(qc: QueryClient, ...queryKeys: QueryKey[]): Promise<void> {
  return Promise.all(queryKeys.map((queryKey) => qc.invalidateQueries({ queryKey }))).then(() => undefined);
}
