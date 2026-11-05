/**
 * The dashboard insight-widget registry: every slice of data the sidebar can
 * show, each backed by an existing API endpoint. The customize dialog renders
 * from this list; saved selections are validated against it so removed
 * widgets degrade silently.
 */
import type { WidgetProps } from "./shell";
import { CryptoWidget, DebtWidget, EquityVestingWidget, NetWorthWidget, RealEstateWidget } from "./widgets/wealth";
import { CashflowNowWidget, MonthlySpendWidget, OutliersWidget, TopCategoriesWidget } from "./widgets/spending";
import { BudgetPaceWidget, SubscriptionsWidget, UpcomingBillsWidget } from "./widgets/planning";
import {
  AllocationWidget, MarketPulseWidget, MonthlyIncomeWidget, PerformanceWidget, PortfolioValueWidget,
} from "./widgets/investing";
import { DataHealthWidget } from "./widgets/system";
import { StatSparkWidget } from "./widgets/stat";

export type WidgetCategory = "Wealth" | "Spending" | "Planning" | "Investing" | "System";

export interface WidgetDef {
  id: string;
  title: string;
  description: string;
  category: WidgetCategory;
  Component: (props: WidgetProps) => React.ReactNode;
}

export const WIDGETS: WidgetDef[] = [
  // ── Wealth ──────────────────────────────────────────────────────────────────
  {
    id: "net_worth",
    title: "Net Worth",
    description: "Total net worth with a one-year trend",
    category: "Wealth",
    Component: NetWorthWidget,
  },
  {
    id: "real_estate",
    title: "Real Estate",
    description: "Property value, mortgage and equity",
    category: "Wealth",
    Component: RealEstateWidget,
  },
  {
    id: "debt",
    title: "Loans & Debt",
    description: "Outstanding balances and average rate",
    category: "Wealth",
    Component: DebtWidget,
  },
  {
    id: "equity_vesting",
    title: "Equity Vesting",
    description: "Vested vs unvested equity and the next vest date",
    category: "Wealth",
    Component: EquityVestingWidget,
  },
  {
    id: "crypto",
    title: "Crypto",
    description: "Crypto value, unrealized gain and top positions",
    category: "Wealth",
    Component: CryptoWidget,
  },
  // ── Spending ────────────────────────────────────────────────────────────────
  {
    id: "cashflow_now",
    title: "This Month",
    description: "Month-to-date income, spending and net",
    category: "Spending",
    Component: CashflowNowWidget,
  },
  {
    id: "monthly_spend",
    title: "Monthly Spend",
    description: "Spending by month for the last year",
    category: "Spending",
    Component: MonthlySpendWidget,
  },
  {
    id: "top_categories",
    title: "Top Categories",
    description: "Biggest spending categories over six months",
    category: "Spending",
    Component: TopCategoriesWidget,
  },
  {
    id: "outliers",
    title: "Unusual Spending",
    description: "Transactions far above their category's typical size",
    category: "Spending",
    Component: OutliersWidget,
  },
  {
    id: "savings_rate",
    title: "Savings Rate",
    description: "Percent of income kept, month by month",
    category: "Spending",
    Component: (p: WidgetProps) => <StatSparkWidget {...p} statKey="savings_rate" title="Savings Rate" />,
  },
  {
    id: "net_cashflow",
    title: "Net Cashflow",
    description: "Income minus spending, month by month",
    category: "Spending",
    Component: (p: WidgetProps) => <StatSparkWidget {...p} statKey="net_cashflow" title="Net Cashflow" />,
  },
  // ── Planning ────────────────────────────────────────────────────────────────
  {
    id: "budget_pace",
    title: "Budget",
    description: "Spent vs planned with a month-pace marker",
    category: "Planning",
    Component: BudgetPaceWidget,
  },
  {
    id: "upcoming_bills",
    title: "Upcoming Bills",
    description: "Recurring charges expected in the next 30 days",
    category: "Planning",
    Component: UpcomingBillsWidget,
  },
  {
    id: "subscriptions",
    title: "Subscriptions",
    description: "Active subscription count and monthly cost",
    category: "Planning",
    Component: SubscriptionsWidget,
  },
  // ── Investing ───────────────────────────────────────────────────────────────
  {
    id: "portfolio_value",
    title: "Portfolio Value",
    description: "Portfolio market value over the last year",
    category: "Investing",
    Component: PortfolioValueWidget,
  },
  {
    id: "allocation",
    title: "Allocation",
    description: "Portfolio by asset class",
    category: "Investing",
    Component: AllocationWidget,
  },
  {
    id: "monthly_income",
    title: "Investment Income",
    description: "Dividends and interest by month",
    category: "Investing",
    Component: MonthlyIncomeWidget,
  },
  {
    id: "performance",
    title: "Performance",
    description: "Year-to-date TWR and XIRR returns",
    category: "Investing",
    Component: PerformanceWidget,
  },
  {
    id: "dividend_income",
    title: "Dividend Income",
    description: "Dividend income trend from the stats system",
    category: "Investing",
    Component: (p: WidgetProps) => <StatSparkWidget {...p} statKey="dividend_income" title="Dividend Income" />,
  },
  {
    id: "market_pulse",
    title: "Markets",
    description: "Index levels and your watchlist's biggest movers",
    category: "Investing",
    Component: MarketPulseWidget,
  },
  // ── System ──────────────────────────────────────────────────────────────────
  {
    id: "data_health",
    title: "Data Health",
    description: "Open reconciliation and data-quality issues",
    category: "System",
    Component: DataHealthWidget,
  },
];

export const WIDGET_MAP: ReadonlyMap<string, WidgetDef> = new Map(WIDGETS.map((w) => [w.id, w]));

export const WIDGET_CATEGORIES: WidgetCategory[] = ["Wealth", "Spending", "Planning", "Investing", "System"];

/** Out-of-the-box selection. Widgets hide themselves when their data source
 *  is empty, so this list can be ambitious without cluttering sparse setups. */
export const DEFAULT_WIDGET_IDS = [
  "net_worth",
  "cashflow_now",
  "budget_pace",
  "upcoming_bills",
  "portfolio_value",
  "monthly_spend",
  "allocation",
];
