import { queryOptions } from "@tanstack/react-query";
import { api } from "./client";
import { keys } from "./keys";
import type { InstanceSettings, DashboardData, SavedReport, ReviewData, NetWorthData, NetWorthProjectionData, NetWorthRange, CashflowSankeyData, ApiToken, FogConnection, WebauthnCredential, BackupOverview, CoinbaseConfiguration, CoinMarketCapConfiguration, AlphaVantageConfiguration, TiingoConfiguration, RentcastConfiguration, OfficeConfiguration, OfficeDataset, OfficeSheetExport, OfficeSpreadsheet, OfficeSpreadsheetPreview, SpreadsheetFormat, RealEstateIndex, RealEstatePropertyDetail, AlchemyConfiguration, AlchemyWallet, CoinbaseAccount, PlaidConfiguration, PlaidItem, AccountWithStats, Broker, CashTransaction, CategorySummary, CategoryDetail, MerchantSummary, MerchantDetail, TagWithStats, TagDetail, SavedView, BuysData, SellsData, DividendsData, PortfolioData, InvestmentTransaction, SecurityDetail, SecuritySummary, TickerSearchResult, CandleData, CandleRange, MarketSummaryData, PortfolioPerformanceData, CashflowData, SpendBreakdownData, SubscriptionsData, SubscriptionDetail, SubscriptionsCalendarData, UpcomingCharge, ActivityData, TransferCandidate, BenchmarkEntry, BenchmarkMeta, TransferSearchResult, SimilarTransactions, TransactionContext, SearchResults, NewsArticle, Household, HouseholdMember, HouseholdInvite, Me, CostBasisData, InvestmentLot, Issue, SecurityConversion, SecurityConversionStatus, Loan, LoanDetail, LoanTransaction, CryptoData, WorkflowSummary, WorkflowDetail, WorkflowCatalog, WorkflowRunsResponse, WorkflowRunGroupsResponse, WorkflowRunDetail, NotificationsResponse, ActivityResponse, ActivityGroupsResponse, ActivityTraceResponse, SystemHealth, BudgetData, BudgetCalendarData, EquitySummary, TaxProfile, TaxReport, StatsIndexData, StatDetailData } from "./types";

export interface DateRange {
  from?: string;
  to?: string;
}

/** "?from=...&to=..." (empty string when the range is open). */
function rangeQS(range?: DateRange): string {
  const params = new URLSearchParams();
  if (range?.from) params.set("from", range.from);
  if (range?.to) params.set("to", range.to);
  const qs = params.toString();
  return qs ? `?${qs}` : "";
}

const withLimit = (qs: string, limit?: number) =>
  limit === undefined ? qs : `${qs}${qs ? "&" : "?"}limit=${limit}`;

const rangeKey = (range?: DateRange) => ({ from: range?.from ?? null, to: range?.to ?? null });

/** Date window plus the cashflow endpoints' optional account/tag/category/
 *  merchant scoping and the sankey's spend dimension. */
export interface CashflowScope extends DateRange {
  account_id?: string;
  tag_id?: string;
  exclude_tag_ids?: string[];
  category_id?: string;
  merchant_id?: string;
  dimension?: string;
}

function scopeQS(scope?: CashflowScope): string {
  const params = new URLSearchParams();
  if (scope?.from) params.set("from", scope.from);
  if (scope?.to) params.set("to", scope.to);
  if (scope?.account_id) params.set("account_id", scope.account_id);
  if (scope?.tag_id) params.set("tag_id", scope.tag_id);
  if (scope?.exclude_tag_ids?.length) params.set("exclude_tag_ids", scope.exclude_tag_ids.join(","));
  if (scope?.category_id) params.set("category_id", scope.category_id);
  if (scope?.merchant_id) params.set("merchant_id", scope.merchant_id);
  if (scope?.dimension) params.set("dimension", scope.dimension);
  const qs = params.toString();
  return qs ? `?${qs}` : "";
}

const scopeKey = (scope?: CashflowScope) => ({
  ...rangeKey(scope),
  account_id: scope?.account_id ?? null,
  tag_id: scope?.tag_id ?? null,
  exclude_tag_ids: scope?.exclude_tag_ids?.length ? [...scope.exclude_tag_ids].sort().join(",") : null,
  category_id: scope?.category_id ?? null,
  merchant_id: scope?.merchant_id ?? null,
  dimension: scope?.dimension ?? null,
});

export const queries = {
  preferences: () => queryOptions({
    queryKey: keys.preferences,
    queryFn: () => api.get<{ data: Record<string, unknown> }>("/preferences").then((r) => r.data),
    staleTime: Infinity,
  }),

  dashboard: (brokerId?: number) => queryOptions({
    queryKey: [...keys.dashboard, brokerId],
    queryFn: () => api.get<DashboardData>(`/dashboard${brokerId ? `?broker_id=${brokerId}` : ""}`),
  }),

  /** A named range, or an explicit window (any timeframe button). With no
   *  `from`, "all" asks for everything on record. */
  netWorth: (window: NetWorthRange | DateRange) => {
    const qs = typeof window === "string" ? `?range=${window}` : window.from ? rangeQS(window) : "?range=all";
    return queryOptions({
      queryKey: [...keys.netWorth, qs],
      queryFn: () => api.get<NetWorthData>(`/net_worth${qs}`),
      staleTime: 5 * 60 * 1000,
    });
  },

  netWorthProjection: (opts: { years: number; growth?: string; monthly?: string }) => {
    const params = new URLSearchParams({ years: String(opts.years) });
    if (opts.growth) params.set("growth", opts.growth);
    if (opts.monthly) params.set("monthly", opts.monthly);
    return queryOptions({
      queryKey: [...keys.netWorth, "projection", opts.years, opts.growth ?? null, opts.monthly ?? null],
      queryFn: () => api.get<NetWorthProjectionData>(`/net_worth/projection?${params.toString()}`),
      staleTime: 5 * 60 * 1000,
    });
  },

  stats: () => queryOptions({
    queryKey: keys.stats,
    queryFn: () => api.get<StatsIndexData>("/stats"),
    staleTime: 5 * 60 * 1000,
  }),

  stat: (key: string, range?: DateRange) => queryOptions({
    queryKey: [...keys.stats, key, rangeKey(range)],
    queryFn: () => api.get<StatDetailData>(`/stats/${key}${rangeQS(range)}`),
    staleTime: 5 * 60 * 1000,
  }),

  apiTokens: () => queryOptions({
    queryKey: keys.apiTokens,
    queryFn: () => api.get<ApiToken[]>("/api_tokens"),
  }),

  // What fog asks on behalf of an app, by the ticket in /connect/<ticket>.
  fogConnection: (ticket: string) => queryOptions({
    queryKey: [...keys.fogConnection, ticket],
    queryFn: () => api.get<FogConnection>(`/fog_connections/${encodeURIComponent(ticket)}`),
    retry: false,
  }),

  // Polls while an artifact is being produced, so the row walks through the
  // producer's progress and turns into a download without a manual refresh.
  backups: () => queryOptions({
    queryKey: keys.backups,
    queryFn: () => api.get<BackupOverview>("/backups"),
    refetchInterval: (query) =>
      query.state.data?.backups.some((b) => b.status === "running") ? 2000 : false,
  }),

  // Instance-wide settings (the time zone) and the zones to choose from.
  instanceSettings: () => queryOptions({
    queryKey: keys.instanceSettings,
    queryFn: () => api.get<InstanceSettings>("/instance_settings"),
  }),

  webauthnCredentials: () => queryOptions({
    queryKey: keys.webauthnCredentials,
    queryFn: () => api.get<WebauthnCredential[]>("/webauthn_credentials"),
  }),

  me: () => queryOptions({
    queryKey: keys.me,
    queryFn: () => api.get<Me>("/me"),
  }),

  about: () => queryOptions({
    queryKey: keys.about,
    queryFn: () => api.get<{ rails_version: string; ruby_version: string; rails_env: string; git_sha: string | null; git_sha_short: string | null; hostname: string }>("/about"),
    staleTime: Infinity,
  }),

  households: () => queryOptions({
    queryKey: keys.households,
    queryFn: () => api.get<Household[]>("/households"),
  }),

  householdMembers: () => queryOptions({
    queryKey: keys.householdMembers,
    queryFn: () => api.get<HouseholdMember[]>("/household_memberships"),
  }),

  householdInvites: () => queryOptions({
    queryKey: keys.invites,
    queryFn: () => api.get<HouseholdInvite[]>("/invites"),
  }),

  transfers: () => queryOptions({
    queryKey: keys.transfers,
    queryFn: () => api.get<TransferCandidate[]>("/transfers?confirmed=true"),
  }),

  transferCandidates: () => queryOptions({
    queryKey: [...keys.transfers, "candidates"],
    queryFn: () => api.get<TransferCandidate[]>("/transfers/candidates"),
  }),

  pendingTransfer: (transactionId: string, transactionType: string) => queryOptions({
    queryKey: [...keys.transfers, "pending", transactionId],
    queryFn: () => api.get<TransferCandidate | null>(
      `/transfers/for_transaction?transaction_id=${transactionId}&transaction_type=${transactionType}`
    ),
  }),

  similarTransactions: (transactionId: string) => queryOptions({
    queryKey: [...keys.cashTransactions, "similar", transactionId],
    queryFn: ({ signal }: { signal?: AbortSignal }) =>
      api.get<SimilarTransactions>(`/cash_transactions/${transactionId}/similar`, { signal }),
  }),

  transactionContext: (transactionId: string) => queryOptions({
    queryKey: [...keys.transactionContext, transactionId],
    queryFn: ({ signal }: { signal?: AbortSignal }) =>
      api.get<TransactionContext>(`/cash_transactions/${transactionId}/context`, { signal }),
  }),

  transferSearch: (transactionId: string) => queryOptions({
    queryKey: [...keys.transferSearch, transactionId],
    queryFn: ({ signal }: { signal?: AbortSignal }) =>
      api.get<TransferSearchResult[]>(`/cash_transactions/transfer_search?transaction_id=${transactionId}`, { signal }),
    enabled: false,
  }),

  search: (q: string) => queryOptions({
    queryKey: [...keys.search, q],
    queryFn: ({ signal }: { signal?: AbortSignal }) =>
      api.get<SearchResults>(`/search?q=${encodeURIComponent(q)}`, { signal }),
    enabled: false,
  }),

  coinbaseConfiguration: () => queryOptions({
    queryKey: keys.coinbaseConfiguration,
    queryFn: () => api.get<CoinbaseConfiguration>("/coinbase/configuration"),
  }),

  coinMarketCapConfiguration: () => queryOptions({
    queryKey: keys.coinMarketCapConfiguration,
    queryFn: () => api.get<CoinMarketCapConfiguration>("/coin_market_cap/configuration"),
  }),

  alphaVantageConfiguration: () => queryOptions({
    queryKey: keys.alphaVantageConfiguration,
    queryFn: () => api.get<AlphaVantageConfiguration>("/alpha_vantage/configuration"),
  }),

  tiingoConfiguration: () => queryOptions({
    queryKey: keys.tiingoConfiguration,
    queryFn: () => api.get<TiingoConfiguration>("/tiingo/configuration"),
  }),

  rentcastConfiguration: () => queryOptions({
    queryKey: keys.rentcastConfiguration,
    queryFn: () => api.get<RentcastConfiguration>("/rentcast/configuration"),
  }),

  // Whether the Office integration is wired up at all — the tables ask before
  // offering "Export to Office", and the answer rarely changes, so it's cached
  // for the session rather than refetched per table mount.
  officeConfiguration: () => queryOptions({
    queryKey: keys.officeConfiguration,
    queryFn: () => api.get<OfficeConfiguration>("/office/configuration"),
    staleTime: 30 * 60 * 1000,
  }),

  // The spreadsheets already linked to a given datatable, so a table can offer
  // "Refresh" on the sheet it made last time instead of piling up copies.
  officeSheetExports: (dataset?: OfficeDataset) => queryOptions({
    queryKey: [...keys.officeSheetExports, dataset ?? "all"],
    queryFn: () =>
      api.get<OfficeSheetExport[]>(`/office/sheet_exports${dataset ? `?dataset=${dataset}` : ""}`),
  }),

  // Spreadsheets in Office that could be imported as transactions.
  officeSpreadsheets: (query: string) => queryOptions({
    queryKey: [...keys.officeSpreadsheets, query],
    queryFn: ({ signal }) =>
      api.get<OfficeSpreadsheet[]>(`/office/spreadsheets${query ? `?query=${encodeURIComponent(query)}` : ""}`, { signal }),
  }),

  // One sheet read and checked as the import would read it. Never cached as
  // fresh: the point of "Check again" is to see an edit just made in Office.
  officeSpreadsheetPreview: (id: number, accountId: string, sheet?: string | null) => queryOptions({
    queryKey: [...keys.officeSpreadsheetPreview, id, accountId, sheet ?? null],
    queryFn: ({ signal }) => {
      const params = new URLSearchParams({ account_id: accountId });
      if (sheet) params.set("sheet", sheet);
      return api.get<OfficeSpreadsheetPreview>(`/office/spreadsheets/${id}/preview?${params}`, { signal });
    },
    staleTime: 0,
    retry: false,
  }),

  // The spreadsheet column layout, as the server checks it. Static.
  importSpreadsheetFormat: () => queryOptions({
    queryKey: keys.importSpreadsheetFormat,
    queryFn: () => api.get<SpreadsheetFormat>("/imports/spreadsheet_format"),
    staleTime: Infinity,
  }),

  coinbaseAccounts: () => queryOptions({
    queryKey: keys.coinbaseAccounts,
    queryFn: () => api.get<CoinbaseAccount[]>("/coinbase/accounts"),
  }),

  alchemyConfiguration: () => queryOptions({
    queryKey: keys.alchemyConfiguration,
    queryFn: () => api.get<AlchemyConfiguration>("/alchemy/configuration"),
  }),

  alchemyWallets: () => queryOptions({
    queryKey: keys.alchemyWallets,
    queryFn: () => api.get<AlchemyWallet[]>("/alchemy/wallets"),
  }),

  plaidConfiguration: () => queryOptions({
    queryKey: keys.plaidConfiguration,
    queryFn: () => api.get<PlaidConfiguration>("/plaid/configuration"),
  }),

  plaidItems: () => queryOptions({
    queryKey: keys.plaidItems,
    queryFn: () => api.get<PlaidItem[]>("/plaid/items"),
  }),

  // Minted by a POST, but cached like a read: link tokens live ~30 min, so
  // refresh well before and don't mint a new one on every focus.
  plaidLinkToken: () => queryOptions({
    queryKey: keys.plaidLinkToken,
    queryFn: () => api.post<{ link_token: string }>("/plaid/link_token"),
    staleTime: 1000 * 60 * 25,
    refetchOnWindowFocus: false,
  }),

  accounts: () => queryOptions({
    queryKey: keys.accounts,
    queryFn: () => api.get<AccountWithStats[]>("/accounts"),
    staleTime: 5 * 60 * 1000,
  }),

  brokers: () => queryOptions({
    queryKey: keys.brokers,
    queryFn: () => api.get<Broker[]>("/brokers"),
  }),

  savedViews: () => queryOptions({
    queryKey: keys.savedViews,
    queryFn: () => api.get<SavedView[]>("/saved_views"),
    staleTime: 5 * 60 * 1000,
  }),

  savedReports: () => queryOptions({
    queryKey: keys.savedReports,
    queryFn: () => api.get<SavedReport[]>("/saved_reports"),
    staleTime: 5 * 60 * 1000,
  }),

  review: (month?: string) => queryOptions({
    queryKey: [...keys.review, month ?? null],
    queryFn: () => api.get<ReviewData>(`/review${month ? `?month=${month}` : ""}`),
    staleTime: 5 * 60 * 1000,
  }),

  /** Live match preview: same evaluator workflows execute with, capped at 8
   *  rows plus an exact total (`count: true`). */
  transactionMatchPreview: (conditions: { field: string; operator: string; value: string }[]) => queryOptions({
    queryKey: [...keys.cashTransactions, "match_preview", conditions] as const,
    queryFn: ({ signal }: { signal?: AbortSignal }) =>
      api.post<{ transactions: CashTransaction[]; total: number }>("/cash_transactions/filter", {
        conditions,
        match_all: true,
        limit: 8,
        count: true,
      }, { signal }),
  }),

  transactions: (filters: Record<string, string>) => {
    const params = new URLSearchParams(filters).toString();
    return queryOptions({
      queryKey: [...keys.cashTransactions, filters],
      queryFn: (ctx?: { signal?: AbortSignal }) =>
        api.get<CashTransaction[]>(`/cash_transactions${params ? `?${params}` : ""}`, { signal: ctx?.signal }),
      staleTime: 5 * 60 * 1000,
    });
  },

  transaction: (id: string) => queryOptions({
    queryKey: [...keys.cashTransactions, id],
    queryFn: () => api.get<CashTransaction>(`/cash_transactions/${id}`),
  }),

  accountTransactions: (accountId: string) => queryOptions({
    queryKey: [...keys.cashTransactions, "account", accountId],
    queryFn: () => api.get<CashTransaction[]>(`/cash_transactions?account_id=${accountId}`),
  }),

  accountHoldings: (accountId: string) => queryOptions({
    queryKey: [...keys.accounts, accountId, "holdings"],
    queryFn: () => api.get<{ as_of_date: string | null; positions: import("./types").Position[] }>(`/accounts/${accountId}/holdings`),
  }),

  loanTransactions: (loanId: string) => queryOptions({
    queryKey: [...keys.cashTransactions, "loan", loanId],
    queryFn: () => api.get<CashTransaction[]>(`/cash_transactions?loan_id=${loanId}`),
  }),

  // The full ledger — the Investments › Transactions page filters, sorts,
  // groups, and pages it client-side.
  allInvestmentTransactions: () => queryOptions({
    queryKey: [...keys.investmentTransactions, "all"],
    queryFn: () => api.get<InvestmentTransaction[]>("/investment_transactions?limit=all"),
  }),

  accountInvestmentTransactions: (accountId: string) => queryOptions({
    queryKey: [...keys.investmentTransactions, "account", accountId],
    queryFn: () => api.get<InvestmentTransaction[]>(`/investment_transactions?account_id=${accountId}`),
  }),

  accountBalanceSnapshots: (accountId: string) => queryOptions({
    queryKey: [...keys.accountBalanceSnapshots, accountId],
    queryFn: () => api.get<{ date: string; balance: number; balance_currency: string; balance_usd: number | null; source: string }[]>(`/accounts/${accountId}/balance_snapshots`),
  }),

  categoryTransactions: (categoryIds: string | string[]) => {
    const ids = Array.isArray(categoryIds) ? categoryIds : [categoryIds];
    const param = ids.length === 1 ? `category_id=${ids[0]}` : `category_ids=${ids.join(",")}`;
    return queryOptions({
      queryKey: [...keys.cashTransactions, "categories", ...ids],
      queryFn: () => api.get<CashTransaction[]>(`/cash_transactions?${param}`),
    });
  },

  merchantTransactions: (merchantId: string) => queryOptions({
    queryKey: [...keys.cashTransactions, "merchant", merchantId],
    queryFn: () => api.get<CashTransaction[]>(`/cash_transactions?merchant_id=${merchantId}`),
  }),

  categories: () => queryOptions({
    queryKey: keys.categories,
    queryFn: () => api.get<CategorySummary[]>("/categories"),
    staleTime: 5 * 60 * 1000,
  }),

  budget: (month: string) => queryOptions({
    queryKey: [...keys.budget, month],
    queryFn: () => api.get<BudgetData>(`/budget?month=${month}`),
  }),
  budgetCalendar: (year: number) => queryOptions({
    queryKey: [...keys.budget, "calendar", year],
    queryFn: () => api.get<BudgetCalendarData>(`/budget/calendar?year=${year}`),
    staleTime: 5 * 60 * 1000,
  }),

  budgetSuggestions: (month: string) => queryOptions({
    queryKey: [...keys.budget, "suggestions", month],
    queryFn: () => api.get<import("./types").BudgetSuggestions>(`/budget/suggestions?month=${month}`),
    staleTime: 5 * 60 * 1000,
  }),

  budgetLineHistory: (month: string, categoryId: string, months = 6) => queryOptions({
    queryKey: [...keys.budget, "line_history", month, categoryId, months],
    queryFn: () =>
      api.get<import("./types").BudgetLineHistory>(
        `/budget/line_history?month=${month}&category_id=${categoryId}&months=${months}`,
      ),
    staleTime: 5 * 60 * 1000,
  }),


  category: (id: string) => queryOptions({
    queryKey: [...keys.categories, id],
    queryFn: () => api.get<CategoryDetail>(`/categories/${id}`),
  }),

  cashflow: (scope?: CashflowScope) => queryOptions({
    queryKey: [...keys.cashflow, scopeKey(scope)],
    queryFn: () => api.get<CashflowData>(`/cashflow${scopeQS(scope)}`),
    staleTime: 5 * 60 * 1000,
  }),
  cashflowSpendBreakdown: (scope?: CashflowScope) => queryOptions({
    queryKey: [...keys.cashflow, "spend_breakdown", scopeKey(scope)],
    queryFn: () => api.get<SpendBreakdownData>(`/cashflow/spend_breakdown${scopeQS(scope)}`),
    staleTime: 5 * 60 * 1000,
  }),
  cashflowSankey: (scope?: CashflowScope) => queryOptions({
    queryKey: [...keys.cashflow, "sankey", scopeKey(scope)],
    queryFn: () => api.get<CashflowSankeyData>(`/cashflow/sankey${scopeQS(scope)}`),
    staleTime: 5 * 60 * 1000,
  }),
  subscriptions: (status: string = "active") => queryOptions({
    queryKey: [...keys.subscriptions, "list", status],
    queryFn: () => api.get<SubscriptionsData>(`/subscriptions?status=${status}`),
    staleTime: 60 * 1000,
  }),
  subscription: (id: string) => queryOptions({
    queryKey: [...keys.subscriptions, "detail", id],
    queryFn: () => api.get<SubscriptionDetail>(`/subscriptions/${id}`),
  }),
  subscriptionsUpcoming: (days: number = 30) => queryOptions({
    queryKey: [...keys.subscriptions, "upcoming", days],
    queryFn: () => api.get<{ upcoming: UpcomingCharge[] }>(`/subscriptions/upcoming?days=${days}`),
    staleTime: 60 * 1000,
  }),
  subscriptionsCalendar: (month: string) => queryOptions({
    queryKey: [...keys.subscriptions, "calendar", month],
    queryFn: () => api.get<SubscriptionsCalendarData>(`/subscriptions/calendar?month=${month}`),
    staleTime: 60 * 1000,
  }),
  cashflowActivity: () => queryOptions({ queryKey: [...keys.cashflow, "activity"], queryFn: () => api.get<ActivityData>("/cashflow/activity"), staleTime: 5 * 60 * 1000 }),
  portfolio: () => queryOptions({ queryKey: keys.portfolio, queryFn: () => api.get<PortfolioData>("/portfolio"), staleTime: 5 * 60 * 1000 }),
  costBasis: () => queryOptions({ queryKey: keys.costBasis, queryFn: () => api.get<CostBasisData>("/cost_basis") }),
  investmentLots: (securityId: string) => queryOptions({
    queryKey: [...keys.investmentLots, securityId],
    queryFn: () => api.get<InvestmentLot[]>(`/investment_lots?security_id=${securityId}`),
  }),
  securities: () => queryOptions({ queryKey: keys.securities, queryFn: () => api.get<SecuritySummary[]>("/market"), staleTime: 5 * 60 * 1000 }),
  securitySearch: (q: string) => queryOptions({
    queryKey: [...keys.securitySearch, q],
    queryFn: ({ signal }: { signal?: AbortSignal }) =>
      api.get<{ results: TickerSearchResult[] }>(`/market/search?q=${encodeURIComponent(q)}`, { signal }),
    staleTime: 10 * 60 * 1000,
  }),
  security: (ticker: string) => queryOptions({ queryKey: [...keys.securities, ticker], queryFn: () => api.get<SecurityDetail>(`/market/${ticker}`) }),
  securityNews: (ticker: string) => queryOptions({ queryKey: [...keys.securities, ticker, "news"], queryFn: () => api.get<NewsArticle[]>(`/market/${ticker}/news`) }),
  securityCandles: (ticker: string, range: CandleRange) => queryOptions({
    queryKey: [...keys.securities, ticker, "candles", range],
    queryFn: () => api.get<CandleData>(`/market/${ticker}/candles?range=${range}`),
    staleTime: 5 * 60 * 1000,
  }),
  marketSummary: () => queryOptions({
    queryKey: keys.marketSummary,
    queryFn: () => api.get<MarketSummaryData>("/market/summary"),
    staleTime: 5 * 60 * 1000,
  }),
  portfolioPerformance: (from?: string) => queryOptions({
    queryKey: [...keys.portfolio, "performance", from ?? "1y"],
    queryFn: () => api.get<PortfolioPerformanceData>(`/portfolio/performance${from ? `?from=${from}` : ""}`),
    staleTime: 5 * 60 * 1000,
  }),
  buys: (range?: DateRange) => queryOptions({ queryKey: [...keys.buys, rangeKey(range)], queryFn: () => api.get<BuysData>(`/buys${rangeQS(range)}`), staleTime: 5 * 60 * 1000 }),
  // `limit` bounds the serialized transactions array (the totals/series are
  // unaffected) — summary consumers pass 1 instead of shipping 500 rows.
  sells: (range?: DateRange, opts?: { limit?: number }) => queryOptions({
    queryKey: [...keys.sells, rangeKey(range), opts?.limit ?? null],
    queryFn: () => api.get<SellsData>(`/sells${withLimit(rangeQS(range), opts?.limit)}`),
    staleTime: 5 * 60 * 1000,
  }),
  dividends: (range?: DateRange, opts?: { limit?: number }) => queryOptions({
    queryKey: [...keys.dividends, rangeKey(range), opts?.limit ?? null],
    queryFn: () => api.get<DividendsData>(`/dividends${withLimit(rangeQS(range), opts?.limit)}`),
    staleTime: 5 * 60 * 1000,
  }),
  crypto: (range?: DateRange) => queryOptions({ queryKey: [...keys.crypto, rangeKey(range)], queryFn: () => api.get<CryptoData>(`/crypto${rangeQS(range)}`), staleTime: 5 * 60 * 1000 }),
  benchmarks: () => queryOptions({ queryKey: keys.benchmarks, queryFn: () => api.get<BenchmarkMeta[]>("/benchmarks") }),
  benchmarkPrices: (symbol: string) => queryOptions({ queryKey: [...keys.benchmark, symbol], queryFn: () => api.get<BenchmarkEntry>(`/benchmarks/${symbol}`) }),

  tags: () => queryOptions({
    queryKey: keys.tags,
    queryFn: () => api.get<TagWithStats[]>("/tags"),
    staleTime: 5 * 60 * 1000,
  }),

  tag: (id: string) => queryOptions({
    queryKey: [...keys.tags, id],
    queryFn: () => api.get<TagDetail>(`/tags/${id}`),
  }),

  tagTransactions: (tagId: string) => queryOptions({
    queryKey: [...keys.cashTransactions, "tag", tagId],
    queryFn: () => api.get<CashTransaction[]>(`/cash_transactions?tag_id=${tagId}`),
  }),

  issues: () => queryOptions({
    queryKey: keys.issues,
    queryFn: () => api.get<Issue[]>("/issues"),
  }),

  // Conversions touching one security on either side, optionally one status.
  securityConversions: (opts: { securityId?: string; status?: SecurityConversionStatus } = {}) => queryOptions({
    queryKey: [...keys.securityConversions, opts],
    queryFn: () => {
      const params = new URLSearchParams();
      if (opts.securityId) params.set("security_id", opts.securityId);
      if (opts.status) params.set("status", opts.status);
      const qs = params.toString();
      return api.get<SecurityConversion[]>(`/security_conversions${qs ? `?${qs}` : ""}`);
    },
  }),


  merchants: () => queryOptions({
    queryKey: keys.merchants,
    queryFn: () => api.get<MerchantSummary[]>("/merchants"),
    staleTime: 5 * 60 * 1000,
  }),

  merchant: (id: string) => queryOptions({
    queryKey: [...keys.merchants, id],
    queryFn: () => api.get<MerchantDetail>(`/merchants/${id}`),
  }),

  loans: () => queryOptions({
    queryKey: keys.loans,
    queryFn: () => api.get<Loan[]>("/loans"),
  }),

  loan: (id: string) => queryOptions({
    queryKey: [...keys.loans, id],
    queryFn: () => api.get<LoanDetail>(`/loans/${id}`),
  }),

  realEstateProperties: () => queryOptions({
    queryKey: keys.realEstateProperties,
    queryFn: () => api.get<RealEstateIndex>("/real_estate_properties"),
  }),

  realEstateProperty: (id: string) => queryOptions({
    queryKey: [...keys.realEstateProperties, id],
    queryFn: () => api.get<RealEstatePropertyDetail>(`/real_estate_properties/${id}`),
  }),

  loanCandidates: (id: string) => queryOptions({
    queryKey: [...keys.loans, id, "candidates"],
    queryFn: () => api.get<LoanTransaction[]>(`/loans/${id}/candidate_transactions`),
  }),

  workflows: () => queryOptions({
    queryKey: keys.workflows,
    queryFn: () => api.get<WorkflowSummary[]>("/workflows"),
  }),

  workflow: (id: string) => queryOptions({
    queryKey: [...keys.workflows, id],
    queryFn: () => api.get<WorkflowDetail>(`/workflows/${id}`),
  }),

  workflowCatalog: () => queryOptions({
    queryKey: keys.workflowCatalog,
    queryFn: () => api.get<WorkflowCatalog>("/workflows/catalog"),
    staleTime: 5 * 60 * 1000,
  }),

  workflowRuns: (filters: { workflowId?: string; status?: string; traceId?: string; page?: number }) => {
    const params = new URLSearchParams();
    if (filters.workflowId) params.set("workflow_id", filters.workflowId);
    if (filters.status) params.set("status", filters.status);
    if (filters.traceId) params.set("trace_id", filters.traceId);
    params.set("page", String(filters.page ?? 1));
    return queryOptions({
      queryKey: [...keys.workflowRuns, filters.workflowId ?? null, filters.status ?? null, filters.traceId ?? null, filters.page ?? 1],
      queryFn: () => api.get<WorkflowRunsResponse>(`/workflow_runs?${params}`),
    });
  },

  workflowRunGroups: (filters: { workflowId?: string; status?: string; page?: number }) => {
    const params = new URLSearchParams();
    if (filters.workflowId) params.set("workflow_id", filters.workflowId);
    if (filters.status) params.set("status", filters.status);
    params.set("grouped", "true");
    params.set("page", String(filters.page ?? 1));
    return queryOptions({
      queryKey: [...keys.workflowRuns, "groups", filters.workflowId ?? null, filters.status ?? null, filters.page ?? 1],
      queryFn: () => api.get<WorkflowRunGroupsResponse>(`/workflow_runs?${params}`),
    });
  },

  workflowRun: (id: string) => queryOptions({
    queryKey: [...keys.workflowRuns, "detail", id],
    queryFn: () => api.get<WorkflowRunDetail>(`/workflow_runs/${id}`),
  }),


  activity: (filters: { source?: string; severity?: string; subjectType?: string; subjectId?: string; page?: number } = {}) => {
    const params = new URLSearchParams();
    if (filters.source) params.set("source", filters.source);
    if (filters.severity) params.set("severity", filters.severity);
    if (filters.subjectType && filters.subjectId) {
      params.set("subject_type", filters.subjectType);
      params.set("subject_id", filters.subjectId);
    }
    params.set("page", String(filters.page ?? 1));
    return queryOptions({
      queryKey: [...keys.activity, filters.source ?? null, filters.severity ?? null, filters.subjectType ?? null, filters.subjectId ?? null, filters.page ?? 1],
      queryFn: () => api.get<ActivityResponse>(`/activity?${params}`),
    });
  },

  activityGroups: (filters: { source?: string; severity?: string; subjectType?: string; subjectId?: string; page?: number } = {}) => {
    const params = new URLSearchParams();
    if (filters.source) params.set("source", filters.source);
    if (filters.severity) params.set("severity", filters.severity);
    if (filters.subjectType && filters.subjectId) {
      params.set("subject_type", filters.subjectType);
      params.set("subject_id", filters.subjectId);
    }
    params.set("grouped", "true");
    params.set("page", String(filters.page ?? 1));
    return queryOptions({
      queryKey: [...keys.activity, "groups", filters.source ?? null, filters.severity ?? null, filters.subjectType ?? null, filters.subjectId ?? null, filters.page ?? 1],
      queryFn: () => api.get<ActivityGroupsResponse>(`/activity?${params}`),
    });
  },

  activityTrace: (traceId: string) => queryOptions({
    queryKey: [...keys.activity, "trace", traceId],
    queryFn: () => api.get<ActivityTraceResponse>(`/activity/trace/${traceId}`),
  }),

  systemHealth: () => queryOptions({
    queryKey: keys.systemHealth,
    queryFn: () => api.get<SystemHealth>("/system_health"),
  }),

  notifications: () => queryOptions({
    queryKey: keys.notifications,
    queryFn: () => api.get<NotificationsResponse>("/notifications"),
    refetchInterval: 60 * 1000,
  }),

  equitySummary: () => queryOptions({
    queryKey: keys.equity,
    queryFn: () => api.get<EquitySummary>("/equity/summary"),
  }),

  taxProfile: (year: number) => queryOptions({
    queryKey: [...keys.taxProfile, year],
    queryFn: () => api.get<TaxProfile>(`/tax_profile?year=${year}`),
  }),

  taxReport: (year: number) => queryOptions({
    queryKey: [...keys.taxReport, year],
    queryFn: () => api.get<TaxReport>(`/tax/report?year=${year}`),
  }),
};
