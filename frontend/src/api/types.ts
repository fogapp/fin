import type { components } from "./schema";

/** Response shapes generated from swagger/v1/swagger.yaml (see frontend/CLAUDE.md). */
type Schemas = components["schemas"];

export type Issue = Schemas["Issue"];

export type SecurityConversion = Schemas["SecurityConversion"];
export type SecurityConversionStatus = Schemas["SecurityConversionStatus"];

export type ReconciliationAcceptResult = Schemas["ReconciliationAcceptResult"];

export type NewsArticle = Schemas["NewsArticle"];

export type WorkflowLogLevel = Household["workflow_log_level"];

export type Household = Schemas["Household"];

export type HouseholdMember = Schemas["HouseholdMembership"];

export type HouseholdInvite = Schemas["Invite"];

/** `POST /invites` adds the shareable accept_url; the list endpoint does not. */
export type InviteCreated = Schemas["InviteCreated"];

export type Me = Schemas["Me"];

/** Login, household switch and household delete all answer with a Session. */
export type Session = Schemas["Session"];

export type InvitePreview = Schemas["InvitePreview"];

/** GET /setup — fresh-instance check, and how people sign in (fog). */
export type SetupStatus = Schemas["SetupStatus"];

/** The fog link page's passkey proof (not a session). */
export type PasskeyLinkProof = Schemas["PasskeyLinkProof"];

/** A one-time token for linking another device's passkey — or, with `host`
 *  and `url` set, a sign-in link for the address the instance is moving to. */
export type DeviceInvite = Schemas["DeviceInvite"];

/** A manually requested backup artifact (Settings → Backup). */
export type Backup = Schemas["Backup"];
export type BackupOverview = Schemas["BackupOverview"];
export type BackupDownload = Schemas["BackupDownload"];
export type BackupKeys = Schemas["BackupKeys"];

/** GET/PATCH /instance_settings — the instance time zone and the selectable zones. */
export type InstanceSettings = Schemas["InstanceSettings"];
export type SelectableTimeZone = InstanceSettings["time_zones"][number];

/** A CSV import and its outcome. */
export type Import = Schemas["Import"];

/** A dry read of a CSV or Office sheet: its format, missing columns, and the
 *  rows that won't import. */
export type ImportPreview = Schemas["ImportPreview"];

/** The column layout a spreadsheet import expects. */
export type SpreadsheetFormat = Schemas["SpreadsheetFormat"];

export type BenchmarkMeta = Schemas["BenchmarkMeta"];

export type BenchmarkEntry = Schemas["BenchmarkEntry"];

export type Broker = Schemas["Broker"];

export type DashboardStats = Schemas["DashboardStats"];

export type CompactStats = Schemas["CompactStats"];

export type RecentTransaction = Schemas["RecentTransaction"];

export type DashboardData = Schemas["DashboardData"];

export type NetWorthRange = Schemas["NetWorthRange"];

export type NetWorthGroup = Schemas["NetWorthGroup"];

/** One sampled point; credit/loans are negative so liabilities stack below zero. */
export type NetWorthSeriesPoint = Schemas["NetWorthSeriesPoint"];

export type NetWorthChange = Schemas["NetWorthChange"];

export type NetWorthStats = Schemas["NetWorthStats"];

export type NetWorthAccountRow = Schemas["NetWorthAccountRow"];

export type NetWorthLoanRow = Schemas["NetWorthLoanRow"];

export type NetWorthPropertyRow = Schemas["NetWorthPropertyRow"];

export type NetWorthEquityRow = Schemas["NetWorthEquityRow"];

export type NetWorthData = Schemas["NetWorthData"];

// ── Real estate ──────────────────────────────────────────────────────────────

export type RealEstateStatus = Schemas["RealEstateStatus"];

/**
 * Where a value came from. Everything but `tax_assessment` counts as market
 * value; assessments are charted as a reference line only, since assessed
 * values run below market by a ratio that varies with the county.
 */
export type RealEstateValuationSource = Schemas["RealEstateValuationSource"];

export type RealEstateValuation = Schemas["RealEstateValuation"];

export type RealEstateProperty = Schemas["RealEstateProperty"];

export type RealEstateFacts = Schemas["RealEstateFacts"];

export type RealEstatePropertyDetail = Schemas["RealEstatePropertyDetail"];

export type RealEstateIndex = Schemas["RealEstateIndex"];

export type RentcastQuota = Schemas["RentcastQuota"];

export type RentcastConfiguration = Schemas["RentcastConfiguration"];

/** Whether this Fin can reach the household's Office instance, and what
 *  it is able to send there. */
export type OfficeConfiguration = Schemas["OfficeConfiguration"];

export type OfficeDataset = Schemas["OfficeDataset"];

/** A Fin datatable linked to one spreadsheet in Office. */
export type OfficeSheetExport = Schemas["OfficeSheetExport"];

/** A spreadsheet in Office that could be imported as transactions. */
export type OfficeSpreadsheet = Schemas["OfficeSpreadsheet"];

/** One Office sheet checked against the spreadsheet import layout. */
export type OfficeSpreadsheetPreview = Schemas["OfficeSpreadsheetPreview"];

export type ApiToken = Schemas["ApiToken"];

/** fog-integration/1 consent: what fog asks for an app at /connect/<ticket>. */
export type FogConnection = Schemas["FogConnection"];
export type FogConnectionAnswer = Schemas["FogConnectionAnswer"];

export type WebauthnCredential = Schemas["WebauthnCredential"];

export type CoinbaseConfiguration = Schemas["CoinbaseConfiguration"];

export type CoinMarketCapConfiguration = Schemas["ApiKeyConfiguration"];

export type AlphaVantageConfiguration = Schemas["ApiKeyConfiguration"];

export type TiingoConfiguration = Schemas["ApiKeyConfiguration"];

export type TickerSearchResult = Schemas["TickerSearchResult"];

export type AlchemySyncFrequency = AlchemyConfiguration["sync_frequency"];

export type AlchemyWebhookStatus = AlchemyConfiguration["webhooks"][number];

export type AlchemyConfiguration = Schemas["AlchemyConfiguration"];

export type AlchemyWalletSync = AlchemyWallet["syncs"][number];

export type AlchemyWallet = Schemas["AlchemyWallet"];

export type CoinbaseAccount = Schemas["CoinbaseAccount"];

export type PlaidConfiguration = Schemas["PlaidConfiguration"];

export type PlaidItem = Schemas["PlaidItem"];

export type Loan = Schemas["Loan"];

export type AmortizationEntry = Schemas["AmortizationEntry"];

export type LoanTransaction = Schemas["LoanTransaction"];

export type LoanDetail = Schemas["LoanDetail"];

export type PlaidAccount = Schemas["PlaidAccount"];

export type Account = Schemas["Account"];

/** `GET /accounts` rows: an Account plus the ledger counts, portfolio value and
 *  linked loan that only the index computes. */
export type AccountWithStats = Schemas["AccountWithStats"];

export type CashTransaction = Schemas["CashTransaction"];

export type BudgetKind = Schemas["BudgetKind"];

/** What create/update return for a category; `GET /categories` rows are CategorySummary. */
export type Category = Schemas["Category"];

export type CategorySummary = Schemas["CategoryWithStats"];

export type SubcategorySummary = Schemas["CategoryDetail"]["subcategories"][number];

export type CategoryDetail = Schemas["CategoryDetail"];

export type RecurringSeriesStatus = Schemas["RecurringSeriesStatus"];
export type RecurringOccurrenceStatus = Schemas["RecurringOccurrenceStatus"];

export type RecurringOccurrence = Schemas["RecurringOccurrence"];

export type SubscriptionsCalendarOccurrence = Schemas["SubscriptionsCalendarOccurrence"];

export type SubscriptionsCalendarData = Schemas["SubscriptionsCalendarData"];

export type RecurringSeries = Schemas["RecurringSeries"];

export type SubscriptionDetail = Schemas["SubscriptionDetail"];

export type SubscriptionsSummary = Schemas["SubscriptionsSummary"];

export type UpcomingCharge = Schemas["UpcomingCharge"];

export type ActivityDay = Schemas["ActivityDay"];

export type ActivityData = Schemas["ActivityData"];

export type SubscriptionsData = Schemas["SubscriptionsData"];

export type CashflowData = Schemas["CashflowData"];

/** A ranked category/merchant total for the By Category / By Merchant panels. */
export type SpendTotal = Schemas["SpendTotal"];

/** One band of a stacked spend chart. `id` is a category/merchant UUID, or
 *  the literal "other" for the remainder bucket. */
export type SpendBreakdownSeries = Schemas["SpendBreakdownSeries"];

export type SpendBreakdown = Schemas["SpendBreakdown"];

/** Monthly spend split by category and by merchant, each with an
 *  outlier-excluded ("common") variant. Its own endpoint rather than part of
 *  CashflowData: only the Spending chart's stacked modes need it. */
export type SpendBreakdownData = Schemas["SpendBreakdownData"];

/** A transaction whose amount cleared its own category's Tukey fence
 * (Q3 + 1.5x IQR of that category's trailing 12-month transaction sizes). */
export type SpendingOutlier = Schemas["SpendingOutlier"];

export type BudgetLineRolledUpChild = Schemas["BudgetLineRolledUpChild"];

export type BudgetLine = Schemas["BudgetLine"];

export type BudgetLineHistoryMonth = Schemas["BudgetLineHistoryMonth"];

export type BudgetLineHistory = Schemas["BudgetLineHistory"];

export type BudgetPeriodKind = Schemas["BudgetPeriodKind"];

/** A line in force is either ongoing (carries forward) or a one-month amount. */
export type BudgetLineMode = BudgetLine["mode"];

export type BudgetPeriod = Schemas["BudgetPeriod"];

export type BudgetSuggestion = Schemas["BudgetSuggestion"];

export type BudgetSuggestions = Schemas["BudgetSuggestions"];

export type BudgetCalendarCell = Schemas["BudgetCalendarCell"];

export type BudgetCalendarRow = Schemas["BudgetCalendarRow"];

export type BudgetCalendarData = Schemas["BudgetCalendarData"];

export type BudgetData = Schemas["BudgetData"];

/** "shortfall" is the savings drawn down when spend exceeds income. */
export type CashflowSankeyNodeKind = Schemas["CashflowSankeyNodeKind"];

export type CashflowSankeyNode = Schemas["CashflowSankeyNode"];

export type CashflowSankeyMember = Schemas["CashflowSankeyMember"];

export type CashflowSankeyGraph = Pick<CashflowSankeyData, "totals" | "nodes" | "links">;

export type CashflowSankeyData = Schemas["CashflowSankeyData"];

export type InstrumentClass = Schemas["InstrumentClass"];

export type PriceSource = Schemas["PriceSource"];

export type LatestPrice = Schemas["LatestPrice"];

export type SecuritySummary = Schemas["SecuritySummary"];

// ── Candles / advanced chart ─────────────────────────────────────────────────

export type CandleRange = Schemas["CandleRange"];

export type CandlePoint = Schemas["CandlePoint"];

export type CorporateEvent = Schemas["CorporateEvent"];

export type CandleData = Schemas["CandleData"];

// ── Market summary (overview dashboard) ──────────────────────────────────────

export type IndexStat = Schemas["IndexStat"];

export type MoverStat = Schemas["MoverStat"];

export type MarketNewsItem = Schemas["MarketNewsItem"];

export type MarketSummaryData = Schemas["MarketSummaryData"];

// ── Portfolio performance (TWR / XIRR) ───────────────────────────────────────

export type PortfolioPerformanceData = Schemas["PortfolioPerformanceData"];

export type SecurityOverview = Schemas["SecurityOverview"];

export type SecurityDetail = Schemas["SecurityDetail"];

export type Position = Schemas["Position"];

export type PortfolioData = Schemas["PortfolioData"];

export type TopSecurity = Schemas["TopSecurity"];

export type InvestmentTransaction = Schemas["InvestmentTransaction"];

export type BuysData = Schemas["BuysData"];

export type SellsData = Schemas["SellsData"];

export type DividendsData = Schemas["DividendsData"];

export type CryptoPosition = Schemas["CryptoPosition"];

export type CryptoData = Schemas["CryptoData"];

export type SavedView = Schemas["SavedView"];

/** Page-state blob a saved report reopens: the section hash (mode toggles
 *  included), the timeframe, and the account/tag scoping (tag exclusions
 *  included). */
export type SavedReportConfig = Schemas["SavedReportConfig"];

export type SavedReport = Schemas["SavedReport"];

export type Tag = Schemas["Tag"];

/** `GET /tags` rows; create/show return a bare Tag. */
export type TagWithStats = Schemas["TagWithStats"];

export type TagDetail = Schemas["TagDetail"];

export type RegistryField = Schemas["RegistryField"];

/** What create/update return for a merchant; `GET /merchants` rows are MerchantSummary. */
export type Merchant = Schemas["Merchant"];

export type MerchantSummary = Schemas["MerchantWithStats"];

export type MerchantDetail = Schemas["MerchantDetail"];

/** A row of the detail pane's "have I paid this before?" list. `match` is
 *  "exact" when the descriptor is identical bar case, "similar" when pg_trgm
 *  scored it close (a different store or order number, typically). */
export type SimilarTransaction = Schemas["SimilarTransaction"];

export type SimilarTransactions = Schemas["SimilarTransactions"];
export type TransactionContext = Schemas["TransactionContext"];
export type TransactionContextRow = Schemas["TransactionContextRow"];
export type TransactionContextNearby = Schemas["TransactionContextNearby"];

export type TransferSearchResult = Schemas["TransferSearchResult"];

// ── Sitewide search (Cmd+K) ─────────────────────────────────────────────────

export type SearchMerchantResult = SearchResults["merchants"][number];

export type SearchCategoryResult = SearchResults["categories"][number];

export type SearchTagResult = SearchResults["tags"][number];

export type SearchAccountResult = SearchResults["accounts"][number];

export type SearchTransactionResult = SearchResults["transactions"][number];

export type SearchLoanResult = SearchResults["loans"][number];

export type SearchInvestmentTransactionResult = SearchResults["investment_transactions"][number];

export type SearchSecurityResult = SearchResults["securities"][number];

export type SearchResults = Schemas["SearchResults"];

export type TransferKind = Transfer["kind"];

export type Transfer = Schemas["Transfer"];

export type InvestmentLotPreview = Schemas["InvestmentLotPreview"];

export type InvestmentLot = Schemas["InvestmentLot"];

/** A lot as the cost-basis endpoint nests it: an InvestmentLot without security_id. */
export type CostBasisLot = Schemas["CostBasisLot"];

export type CostBasisPosition = Schemas["CostBasisPosition"];

export type CostBasisData = Schemas["CostBasisData"];

// ── Workflows ─────────────────────────────────────────────────────────────────

export type WorkflowStepKind = Schemas["WorkflowStepKind"];

export type WorkflowStep = Schemas["WorkflowStep"];

/** Steps as submitted on save — the backend replaces the tree wholesale, so no ids. */
export interface WorkflowStepInput {
  kind: WorkflowStepKind;
  config: Record<string, unknown>;
  children: WorkflowStepInput[];
}

export type Workflow = Schemas["Workflow"];

export type WorkflowSummary = Schemas["WorkflowSummary"];

export type WorkflowDetail = Schemas["WorkflowDetail"];

export type WorkflowCatalogTrigger = WorkflowCatalog["triggers"][number];

export type WorkflowCatalog = Schemas["WorkflowCatalog"];

export type WorkflowRunStatus = Schemas["WorkflowRunStatus"];

export type WorkflowRun = Schemas["WorkflowRun"];

export type WorkflowRunRevertResult = Schemas["WorkflowRunRevertResult"];

export type WorkflowRunStepStatus = WorkflowRunStep["status"];

export type WorkflowRunStep = Schemas["WorkflowRunStep"];

export type WorkflowRunDetail = Schemas["WorkflowRunDetail"];

export type WorkflowRunsResponse = Schemas["WorkflowRunsResponse"];

export type WorkflowRunGroup = Schemas["WorkflowRunGroup"];

export type WorkflowRunGroupsResponse = Schemas["WorkflowRunGroupsResponse"];

export type NotificationSeverity = AppNotification["severity"];

export type AppNotification = Schemas["AppNotification"];

export type NetWorthProjectionData = Schemas["NetWorthProjectionData"];

export type ReviewRankedRow = Schemas["ReviewRankedRow"];

export type ReviewData = Schemas["ReviewData"];

export type NotificationsResponse = Schemas["NotificationsResponse"];

// ── Activity / observability ──────────────────────────────────────────────────

export type ActivitySeverity = Schemas["ActivitySeverity"];

export type ActivityEntry = Schemas["ActivityEntry"];

export type ActivityResponse = Schemas["ActivityResponse"];

export type ActivityGroup = Schemas["ActivityGroup"];

export type ActivityGroupsResponse = Schemas["ActivityGroupsResponse"];

export type ActivityTraceNotification = ActivityTraceResponse["notifications"][number];

export type ActivityTraceResponse = Schemas["ActivityTraceResponse"];

export type SystemHealthSource = SystemHealth["sources"][number];

export type MarketDataProvider = MarketDataHealth["providers"][number];

export type MarketDataHealth = SystemHealth["market_data"];

export type SystemHealth = Schemas["SystemHealth"];

export type TransferCandidate = Schemas["TransferWithDetails"];

// ── Equity compensation ───────────────────────────────────────────────────────

export type EquityGrantType = Schemas["EquityGrantType"];
export type EquityEventKind = Schemas["EquityEventKind"];

export type EquityFmvEntry = Schemas["EquityFmvEntry"];

export type EquityGrantEvent = Schemas["EquityGrantEvent"];

export type EquityTranche = Schemas["EquityTranche"];

export type EquityGrant = Schemas["EquityGrant"];

export type EquityCompany = Schemas["EquityCompany"];

export type EquityUpcomingVest = Schemas["EquityUpcomingVest"];

export type EquitySummary = Schemas["EquitySummary"];

// ── Exercise planner / tax profile ────────────────────────────────────────────

export type TaxProfile = Schemas["TaxProfile"];

export type ExercisePlanScenario = Schemas["ExercisePlanScenario"];

export type ExercisePlanNsoGap = Schemas["ExercisePlanNsoGap"];

export type ExercisePlanSafeHarbor = Schemas["ExercisePlanSafeHarbor"];

export type ExercisePlan = Schemas["ExercisePlan"];

// ── Tax center ────────────────────────────────────────────────────────────────

export type TaxKind = Schemas["TaxKind"];

export type TaxEstimatedPayment = Schemas["TaxEstimatedPayment"];

export type TaxChecklistItem = Schemas["TaxChecklistItem"];

export type TaxAdjustment = Schemas["TaxAdjustment"];

export type TaxAdjustmentGroup = Schemas["TaxAdjustmentGroup"];

export type TaxSafeHarbor = Schemas["TaxSafeHarbor"];

export type TaxJurisdictionLiability = Schemas["TaxJurisdictionLiability"];

export type TaxReport = Schemas["TaxReport"];


// ── Stats ─────────────────────────────────────────────────────────────────────

export type StatUnit = Schemas["StatUnit"];
export type StatGranularity = Schemas["StatGranularity"];
export type StatValueType = Schemas["StatValueType"];
export type StatDirection = Schemas["StatDirection"];

/** Monthly stats use "YYYY-MM" dates; daily stats use "YYYY-MM-DD". */
export type StatPoint = Schemas["StatPoint"];

export type StatDrill = Schemas["StatDrill"];

/** Projection of an in-flight flow period to its full length. */
export type StatPace = Schemas["StatPace"];


export type StatSummary = Schemas["StatSummary"];

export type StatsIndexData = Schemas["StatsIndexData"];

export type StatBreakdownRow = Schemas["StatBreakdownRow"];

export type StatBreakdown = Schemas["StatBreakdown"];

export type StatDetailData = Schemas["StatDetailData"];
