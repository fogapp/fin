import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, fireEvent, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

vi.mock("@simplewebauthn/browser", () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api, clearToken } from "@/api/client";
import { renderApp } from "@/test/renderApp";
import { timeframeRange } from "@/components/charts";
import type { Account, ActivityData, CashflowData, CashflowSankeyData, CashTransaction, SpendBreakdownData, TransferCandidate } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

/** "yyyy-mm" key for the month `offset` months before the current one. */
function monthKey(offset: number): string {
  const now = new Date();
  const d = new Date(now.getFullYear(), now.getMonth() - offset, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

const THIS_MONTH = monthKey(0);
const LAST_MONTH = monthKey(1);

const CASHFLOW: CashflowData = {
  summary: {
    mtd_income: 5000, mtd_spend: 2000, mtd_spend_common: 1500, mtd_net: 3000,
    lmo_income: 6000, lmo_spend: 2500, lmo_spend_common: 2500,
    ytd_income: 40000, ytd_spend: 15000, ytd_spend_common: 13500, ytd_net: 25000,
    savings_rate_ytd: 62.5,
  },
  monthly_income: { [LAST_MONTH]: 6000, [THIS_MONTH]: 5000 },
  monthly_spend: { [LAST_MONTH]: 2500, [THIS_MONTH]: 2000 },
  monthly_spend_common: { [LAST_MONTH]: 2500, [THIS_MONTH]: 1500 },
  top_categories: [
    { id: "cat-groceries", name: "Groceries", amount: 4200.5, avg_monthly: 350.04, largest: 210.5 },
    { id: "cat-dining",    name: "Dining",     amount: 1800,   avg_monthly: 150,    largest: 1800 },
  ],
  top_categories_common: [
    { id: "cat-groceries", name: "Groceries", amount: 4200.5, avg_monthly: 350.04, largest: 210.5 },
  ],
  top_merchants: [
    { id: "mer-costco", name: "Costco",        amount: 3100,    avg_monthly: 258.33, largest: 400 },
    { id: "mer-tj",     name: "Trader Joe's",  amount: 1100.25, avg_monthly: 91.69,  largest: 150 },
  ],
  top_merchants_common: [
    { id: "mer-costco", name: "Costco",        amount: 3100,    avg_monthly: 258.33, largest: 400 },
    { id: "mer-tj",     name: "Trader Joe's",  amount: 1100.25, avg_monthly: 91.69,  largest: 150 },
  ],
  top_income_sources: { "Acme Payroll": 38000, Interest: 2000 },
  outliers: [],
};

/** Each month's bands sum to that month's monthly_spend above — the Total
 *  line and a stacked month are the same number, split up. */
const SPEND_BREAKDOWN: SpendBreakdownData = {
  from: `${LAST_MONTH}-01`,
  to: `${THIS_MONTH}-28`,
  monthly_spend: { [`${LAST_MONTH}-01`]: 2500, [`${THIS_MONTH}-01`]: 2000 },
  monthly_spend_common: { [`${LAST_MONTH}-01`]: 2500, [`${THIS_MONTH}-01`]: 1500 },
  category: {
    series: [
      { id: "cat-groceries", name: "Groceries" },
      { id: "cat-dining", name: "Dining" },
      { id: "other", name: "Other" },
    ],
    months: {
      [`${LAST_MONTH}-01`]: { "cat-groceries": 1600, "cat-dining": 700, other: 200 },
      [`${THIS_MONTH}-01`]: { "cat-groceries": 1300, "cat-dining": 500, other: 200 },
    },
  },
  category_common: {
    series: [{ id: "cat-groceries", name: "Groceries" }, { id: "other", name: "Other" }],
    months: {
      [`${LAST_MONTH}-01`]: { "cat-groceries": 2300, other: 200 },
      [`${THIS_MONTH}-01`]: { "cat-groceries": 1300, other: 200 },
    },
  },
  merchant: {
    series: [
      { id: "mer-costco", name: "Costco" },
      { id: "mer-tj", name: "Trader Joe's" },
      { id: "other", name: "Other" },
    ],
    months: {
      [`${LAST_MONTH}-01`]: { "mer-costco": 1500, "mer-tj": 600, other: 400 },
      [`${THIS_MONTH}-01`]: { "mer-costco": 1200, "mer-tj": 500, other: 300 },
    },
  },
  merchant_common: {
    series: [{ id: "mer-costco", name: "Costco" }, { id: "other", name: "Other" }],
    months: {
      [`${LAST_MONTH}-01`]: { "mer-costco": 2100, other: 400 },
      [`${THIS_MONTH}-01`]: { "mer-costco": 1200, other: 300 },
    },
  },
};

const CASH_TRANSACTIONS: CashTransaction[] = [
  {
    id: "tx-1", source: "credit_card", transaction_date: "2026-06-15",
    transfer_id: null, transfer_kind: null, transfer_include_in_spend: null,
    post_date: "2026-06-17", description: "COSTCO WHSE #123", amount: -180.22,
    transaction_type: "Sale", category_id: "cat-groceries", category_name: "Groceries",
    // No merchant_name — the row falls back to the raw description, giving the
    // test unambiguous text to assert on ("Costco" also appears in By Merchant).
    merchant_id: null, merchant_name: null,
    account_id: "a1", account_name: "Everyday Checking",
    balance: null, memo: null, loan_id: null, loan_name: null, tags: [],
    created_at: "2026-06-15T12:00:00Z",
  },
];

const SANKEY: CashflowSankeyData = {
  from: "2025-07-03",
  to: "2026-07-03",
  totals: { income: 40000, spend: 15000, savings: 25000 },
  nodes: [
    { name: "Acme Payroll", kind: "income_source", merchant_id: "m-acme" },
    { name: "Income", kind: "hub" },
    { name: "Groceries", kind: "category", category_id: "c-groc" },
    { name: "Savings", kind: "savings" },
  ],
  links: [
    { source: 0, target: 1, value: 40000 },
    { source: 1, target: 2, value: 15000 },
    { source: 1, target: 3, value: 25000 },
  ],
  common: {
    totals: { income: 40000, spend: 9000, savings: 31000 },
    nodes: [
      { name: "Acme Payroll", kind: "income_source", merchant_id: "m-acme" },
      { name: "Income", kind: "hub" },
      { name: "Groceries", kind: "category", category_id: "c-groc" },
      { name: "Savings", kind: "savings" },
    ],
    links: [
      { source: 0, target: 1, value: 40000 },
      { source: 1, target: 2, value: 9000 },
      { source: 1, target: 3, value: 31000 },
    ],
    outlier_transaction_ids: ["tx-outlier"],
  },
};

const SAVED_REPORTS = [
  {
    id: "r1",
    name: "Common flow · 3M",
    config: { hash: "section=flow&mode=common", preset: "3m", custom_range: null, account_id: null, tag_id: null },
    created_at: "2026-08-01T00:00:00Z",
  },
];

const ACTIVITY: ActivityData = {
  days: [
    { date: "2026-06-28", spend: 0, income: 0 },
    { date: "2026-06-30", spend: 120.5, income: 0 },
    { date: "2026-07-01", spend: 0, income: 2500 },
    { date: "2026-07-02", spend: 45, income: 0 },
  ],
  total_spend: 165.5,
  total_income: 2500,
  net: 2334.5,
};

function account(id: string, name: string, overrides: Partial<Account> = {}): Account {
  return {
    id, name, account_number: "1234", kind: "standard", account_type: "Checking",
    balance: 1000, balance_currency: "USD", balance_usd: 1000,
    broker_id: "b1", broker_name: "Chase", plaid_item_id: null,
    cash_transaction_count: 10, investment_transaction_count: 0,
    portfolio_value: 0, latest_transaction_date: "2026-07-01",
    linked_loan_id: null, hidden: false,
    ...overrides,
  };
}

const ACCOUNTS: Account[] = [
  account("a1", "Everyday Checking"),
  account("a2", "High-Yield Savings"),
  account("ext1", "Schwab", { kind: "external", broker_id: null as unknown as string, broker_name: null as unknown as string }),
];

const CONFIRMED_TRANSFER: TransferCandidate = {
  id: "tr-1",
  from_transaction_id: "t1", from_transaction_type: "CashTransaction",
  to_transaction_id: "t2", to_transaction_type: "CashTransaction",
  counterparty_account_id: null, counterparty_account_name: null,
  amount: 500, note: null,
  confirmed_at: "2026-06-20T00:00:00Z", created_at: "2026-06-20T00:00:00Z",
  from_date: "2026-06-18", from_description: "ONLINE TRANSFER TO SAVINGS",
  from_account_id: "a1",
  to_date: "2026-06-19", to_description: "ONLINE TRANSFER FROM CHECKING",
  to_account_id: "a2", date_diff: 1,
};

/** One-sided transfer to an external account (no counterpart transaction). */
const EXTERNAL_TRANSFER: TransferCandidate = {
  id: "tr-ext",
  from_transaction_id: "t5", from_transaction_type: "CashTransaction",
  to_transaction_id: null, to_transaction_type: null,
  counterparty_account_id: "ext1", counterparty_account_name: "Schwab",
  amount: 250, note: null,
  confirmed_at: "2026-07-02T00:00:00Z", created_at: "2026-07-02T00:00:00Z",
  from_date: "2026-07-02", from_description: "SCHWAB BROKERAGE XFER",
  from_account_id: "a1",
  to_date: null, to_description: null,
  to_account_id: null, date_diff: null,
};

const CANDIDATE: TransferCandidate = {
  id: "cand-1",
  from_transaction_id: "t3", from_transaction_type: "CashTransaction",
  to_transaction_id: "t4", to_transaction_type: "CashTransaction",
  counterparty_account_id: null, counterparty_account_name: null,
  amount: 1200, note: null,
  confirmed_at: null, created_at: "2026-06-30T00:00:00Z",
  from_date: "2026-06-28", from_description: "ACH WITHDRAWAL VANGUARD",
  from_account_id: "a1",
  to_date: "2026-06-30", to_description: "ACH DEPOSIT",
  to_account_id: "a2", date_diff: 2,
};

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  apiMock.post.mockResolvedValue({} as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/saved_reports") return SAVED_REPORTS as never;
    if (path === "/cashflow/activity") return ACTIVITY as never;
    if (path.startsWith("/cashflow/sankey")) return SANKEY as never;
    if (path.startsWith("/cashflow/spend_breakdown")) return SPEND_BREAKDOWN as never;
    if (path.startsWith("/cashflow")) return CASHFLOW as never; // "?from=…&to=…" range params
    if (path.startsWith("/cash_transactions")) return CASH_TRANSACTIONS as never;
    if (path === "/transfers?confirmed=true") return [CONFIRMED_TRANSFER, EXTERNAL_TRANSFER] as never;
    if (path === "/transfers/candidates") return [CANDIDATE] as never;
    if (path === "/accounts") return ACCOUNTS as never;
    return [] as never;
  });
});

describe("Cashflow: Activity section (default)", () => {
  it("renders stats and the daily breakdown table", async () => {
    renderApp({ initialPath: "/cashflow", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Activity" })).toBeInTheDocument();
    expect(screen.getByText("past 30 days")).toBeInTheDocument();

    // Stat ribbon (compact currency)
    expect(screen.getByText("$165.5")).toBeInTheDocument();  // spend
    expect(screen.getByText("$2.5K")).toBeInTheDocument();   // income
    expect(screen.getByText("$2.3K")).toBeInTheDocument();   // net

    // Daily breakdown rows (reversed, zero days filtered out)
    expect(screen.getByRole("button", { name: "2026-07-01" })).toBeInTheDocument();
    expect(screen.getByText("$2,500.00")).toBeInTheDocument();
    expect(screen.getByText("+$2,500.00")).toBeInTheDocument();
    expect(screen.getByText("-$120.50")).toBeInTheDocument();
    expect(screen.queryByText("2026-06-28")).not.toBeInTheDocument();
  });

  it("clicking a date stores a transaction-date filter and navigates to /transactions", async () => {
    renderApp({ initialPath: "/cashflow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Activity" });

    fireEvent.click(screen.getByRole("button", { name: "2026-06-30" }));

    await waitFor(() => {
      const stored = sessionStorage.getItem("txn_filters:/transactions");
      expect(stored).not.toBeNull();
      expect(JSON.parse(stored!)).toEqual([
        { _key: 1, field: "transaction_date", operator: "equals", value: "2026-06-30" },
      ]);
      // Landed on the transactions page — activity heading is gone
      expect(screen.queryByRole("heading", { name: "Activity" })).not.toBeInTheDocument();
    });
  });
});

describe("Cashflow: Spending section", () => {
  it("renders spend stats, chart labels, and YTD category/merchant tables", async () => {
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Spending" })).toBeInTheDocument();

    // Stat ribbon
    expect(screen.getByText("$2,000.00")).toBeInTheDocument(); // MTD
    expect(screen.getByText("$2,500.00")).toBeInTheDocument(); // last month
    expect(screen.getByText("$15K")).toBeInTheDocument();      // YTD compact
    expect(screen.getByText("$346.15")).toBeInTheDocument();   // avg / month = 4500 / 13 (1Y window)

    // Chart card titles (recharts SVG is empty in jsdom)
    expect(screen.getByText("Monthly Spend")).toBeInTheDocument();
    expect(screen.getByText("By Category")).toBeInTheDocument();
    expect(screen.getByText("By Merchant")).toBeInTheDocument();
    expect(screen.getByText("Outliers")).toBeInTheDocument();
    expect(screen.getByText("Nothing unusual")).toBeInTheDocument();

    // The page-scoped timeframe control lives in the subheader, next to the
    // Common/Outlier/Both series toggle — both scope the whole page.
    expect(screen.getByRole("group", { name: "Timeframe" })).toBeInTheDocument();
    const seriesToggle = screen.getByRole("group", { name: "Spend series" });
    expect(within(seriesToggle).getByText("Common")).toBeInTheDocument();
    expect(within(seriesToggle).getByText("Outlier")).toBeInTheDocument();
    expect(within(seriesToggle).getByText("Both")).toBeInTheDocument();

    // YTD tables
    expect(screen.getAllByText("Groceries").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Dining").length).toBeGreaterThan(0);
    expect(screen.getByText("$4,200.50")).toBeInTheDocument();
    expect(screen.getAllByText("Costco").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Trader Joe's").length).toBeGreaterThan(0);
    expect(screen.getByText("$1,100.25")).toBeInTheDocument();
  });

  it("switching to Common filters the ribbon and category panel page-wide, not just the chart", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Spending" });

    // Total/"Both" view first
    expect(screen.getByText("$2,000.00")).toBeInTheDocument(); // MTD total
    expect(screen.getAllByText("Dining").length).toBeGreaterThan(0);

    await user.click(within(screen.getByRole("group", { name: "Spend series" })).getByText("Common"));

    // Ribbon switches to the outlier-excluded totals
    expect(screen.getByText("$1,500.00")).toBeInTheDocument(); // MTD common
    expect(screen.getByText("$13.5K")).toBeInTheDocument();    // YTD common, compact
    expect(screen.getByText("$307.69")).toBeInTheDocument();   // avg/month common = 4000 / 13

    // Dining's only spend was the flagged outlier — it drops out of the common view
    expect(screen.queryByText("Dining")).not.toBeInTheDocument();
    expect(screen.getAllByText("Groceries").length).toBeGreaterThan(0);
  });

  it("shows avg/largest under each row and lists transactions for the timeframe", async () => {
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Spending" });

    // Subtle avg/largest line under each bar
    expect(screen.getByText("$350.04/mo avg · $210.50 largest")).toBeInTheDocument();
    expect(screen.getByText("$258.33/mo avg · $400.00 largest")).toBeInTheDocument();

    // Transactions card, scoped to the page timeframe, unfiltered by default
    // ("Transactions" also names the sidebar nav link, so scope to the heading)
    expect(await screen.findByRole("heading", { name: "Transactions" })).toBeInTheDocument();
    expect(await screen.findByText("COSTCO WHSE #123")).toBeInTheDocument();
    expect(screen.queryByText("Clear filter")).not.toBeInTheDocument();
  });

  it("clicking a category row filters the transactions list and can be cleared", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Spending" });
    await screen.findByText("COSTCO WHSE #123");

    await user.click(screen.getByText("Groceries"));

    // api.get is called with a second ({signal}) argument, so match on the
    // recorded path rather than toHaveBeenCalledWith(oneArg) (which requires
    // the call's full argument list, not just a prefix, to match).
    await waitFor(() => {
      const paths = apiMock.get.mock.calls.map((c) => c[0]);
      expect(paths.some((p) => /^\/cash_transactions\?.*category_id=cat-groceries/.test(p))).toBe(true);
    });
    expect(screen.getByText("Filtered by Groceries")).toBeInTheDocument();

    await user.click(screen.getByText("Clear filter"));
    expect(screen.queryByText("Filtered by Groceries")).not.toBeInTheDocument();
  });
});

describe("Cashflow: Spending chart splits", () => {
  const splitToggle = () => screen.getByRole("group", { name: "Spend split" });

  it("does not fetch the breakdown until a split is picked, then scopes it to the page timeframe", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Spending" });

    // The default Total view costs nothing extra — the breakdown is its own
    // endpoint precisely so most page loads never pay for it.
    const requested = () => apiMock.get.mock.calls.map((c) => c[0]).filter((p: string) => p.startsWith("/cashflow/spend_breakdown"));
    expect(requested()).toHaveLength(0);
    expect(screen.queryByRole("group", { name: "Spend scale" })).not.toBeInTheDocument();

    await user.click(within(splitToggle()).getByText("Category"));

    const { from, to } = timeframeRange("1y");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/spend_breakdown?from=${from}&to=${to}`);
    });
  });

  it("says what the bands are, and switches between amounts and shares", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Spending" });

    await user.click(within(splitToggle()).getByText("Category"));
    expect(await screen.findByText(/Each month's spend by category · top 8, everything else in Other/)).toBeInTheDocument();

    // The scale toggle only exists once there is something to normalize.
    await user.click(within(screen.getByRole("group", { name: "Spend scale" })).getByText("%"));
    expect(screen.getByText(/Share of each month's spend by category/)).toBeInTheDocument();

    await user.click(within(splitToggle()).getByText("Merchant"));
    expect(screen.getByText(/Share of each month's spend by merchant/)).toBeInTheDocument();

    // Back to Total: no split, no scale control, no subtitle.
    await user.click(within(splitToggle()).getByText("Total"));
    expect(screen.queryByRole("group", { name: "Spend scale" })).not.toBeInTheDocument();
    expect(screen.queryByText(/everything else in Other/)).not.toBeInTheDocument();
  });

  it("shows an empty state rather than an all-gray stack when nothing is attributed", async () => {
    const base = apiMock.get.getMockImplementation()!;
    apiMock.get.mockImplementation(async (path: string, ...rest: unknown[]) => {
      if (path.startsWith("/cashflow/spend_breakdown")) {
        return {
          ...SPEND_BREAKDOWN,
          // Every dollar fell into the remainder — no merchant was attributed.
          merchant: { series: [{ id: "other", name: "Other" }], months: { [`${THIS_MONTH}-01`]: { other: 2000 } } },
        } as never;
      }
      return base(path, ...(rest as [])) as never;
    });

    const user = userEvent.setup();
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Spending" });

    await user.click(within(splitToggle()).getByText("Merchant"));

    expect(await screen.findByText("No merchant spending")).toBeInTheDocument();
    expect(screen.getByText("Nothing to split up in this timeframe.")).toBeInTheDocument();
  });

  it("scopes the split to the page's Common toggle without refetching", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Spending" });

    await user.click(within(splitToggle()).getByText("Category"));
    await screen.findByText(/Each month's spend by category/);
    const callsBefore = apiMock.get.mock.calls.length;

    // Both variants ship in one response, so the page-wide toggle is instant.
    await user.click(within(screen.getByRole("group", { name: "Spend series" })).getByText("Common"));
    expect(screen.getByText(/Each month's spend by category · top 8, everything else in Other · excl. outliers/)).toBeInTheDocument();
    expect(apiMock.get.mock.calls.length).toBe(callsBefore);
  });
});

describe("Cashflow: Income section", () => {
  it("renders income stats, savings rate, and income sources", async () => {
    renderApp({ initialPath: "/cashflow#section=income", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Income" })).toBeInTheDocument();

    // Stat ribbon
    expect(screen.getByText("$5,000.00")).toBeInTheDocument(); // MTD
    expect(screen.getByText("$6,000.00")).toBeInTheDocument(); // last month
    expect(screen.getByText("$40K")).toBeInTheDocument();      // YTD compact
    expect(screen.getByText("$846.15")).toBeInTheDocument();   // avg = 11000 / 13 (1Y window)
    expect(screen.getByText("62.5%")).toBeInTheDocument();     // savings rate

    // Income sources table
    expect(screen.getByText("Income Sources — YTD")).toBeInTheDocument();
    expect(screen.getByText("Acme Payroll")).toBeInTheDocument();
    expect(screen.getByText("$38,000.00")).toBeInTheDocument();
    expect(screen.getByText("Interest")).toBeInTheDocument();
  });
});

describe("Cashflow: Money Flow section", () => {
  it("renders totals and requests the sankey scoped to the page timeframe", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Money Flow" })).toBeInTheDocument();

    // Totals ribbon (compact currency)
    expect(screen.getByText("$40K")).toBeInTheDocument();  // income
    expect(screen.getByText("$15K")).toBeInTheDocument();  // spend
    expect(screen.getByText("$25K")).toBeInTheDocument();  // savings

    // Sankey query carries the default 1Y window
    const { from, to } = timeframeRange("1y");
    expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/sankey?from=${from}&to=${to}`);
  });

  it("changing the timeframe preset re-queries with the new range", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });

    fireEvent.click(screen.getByRole("button", { name: "3M" }));

    const { from, to } = timeframeRange("3m");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/sankey?from=${from}&to=${to}`);
    });
    // The heavy /cashflow payload is only consumed by Spending/Income — it
    // must not fetch while the Flow section is open.
    expect(apiMock.get).not.toHaveBeenCalledWith(`/cashflow?from=${from}&to=${to}`);
  });

  it("applies a custom date range from the Custom panel", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });

    fireEvent.click(screen.getByRole("button", { name: "Custom" }));
    fireEvent.change(screen.getByLabelText("From"), { target: { value: "2026-01-01" } });
    fireEvent.change(screen.getByLabelText("To"), { target: { value: "2026-03-31" } });
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/cashflow/sankey?from=2026-01-01&to=2026-03-31");
    });
  });

  it("scoping to an account re-queries with account_id", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });

    fireEvent.change(await screen.findByLabelText("Account filter"), { target: { value: "a1" } });

    const { from, to } = timeframeRange("1y");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/sankey?from=${from}&to=${to}&account_id=a1`);
    });
  });

  it("switching to Common swaps in the outlier-excluded totals without re-querying", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });
    expect(screen.getByText("$15K")).toBeInTheDocument();
    const sankeyCalls = apiMock.get.mock.calls.filter(([path]) => String(path).startsWith("/cashflow/sankey")).length;

    const toggle = screen.getByRole("group", { name: "Flow transactions" });
    fireEvent.click(within(toggle).getByText("Common"));

    expect(screen.getByText("$9K")).toBeInTheDocument();    // common spend
    expect(screen.getByText("$31K")).toBeInTheDocument();   // common savings
    expect(screen.queryByText("$15K")).not.toBeInTheDocument();
    const after = apiMock.get.mock.calls.filter(([path]) => String(path).startsWith("/cashflow/sankey")).length;
    expect(after).toBe(sankeyCalls);
  });
});

describe("Cashflow: timeframe buttons", () => {
  /** Re-routes /preferences to a saved row; everything else keeps the default stub. */
  function withPrefs(data: Record<string, unknown>) {
    const base = apiMock.get.getMockImplementation()!;
    apiMock.get.mockImplementation(async (path: string, ...rest: unknown[]) => {
      if (path === "/preferences") return { data } as never;
      return (base as (p: string, ...r: unknown[]) => Promise<never>)(path, ...rest);
    });
  }

  it("offers month-to-date and last month by default", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });

    const group = screen.getByRole("group", { name: "Timeframe" });
    const lastMonth = new Date(new Date().getFullYear(), new Date().getMonth() - 1, 1)
      .toLocaleDateString("en-US", { month: "short" });
    expect(within(group).getAllByRole("button").map((b) => b.textContent))
      .toEqual(["MTD", lastMonth, "3M", "6M", "1Y", "YTD", "All", "Custom"]);

    fireEvent.click(within(group).getByRole("button", { name: lastMonth }));
    const { from, to } = timeframeRange("last_month");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/sankey?from=${from}&to=${to}`);
    });
  });

  it("uses the row and default saved in Settings", async () => {
    withPrefs({
      timeframes: {
        buttons: [
          { type: "builtin", key: "mtd" },
          { type: "fixed", id: "c_fy", label: "FY24", from: "2023-10-01", to: "2024-09-30" },
        ],
        defaults: { cashflow: "c_fy" },
      },
    });
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });

    const group = screen.getByRole("group", { name: "Timeframe" });
    await waitFor(() => {
      expect(within(group).getByRole("button", { name: "FY24" })).toHaveAttribute("aria-pressed", "true");
    });
    expect(within(group).queryByRole("button", { name: "1Y" })).toBeNull();
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/cashflow/sankey?from=2023-10-01&to=2024-09-30");
    });
  });

  it("labels Spending panels with the selected button's description", async () => {
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Spending" });

    fireEvent.click(screen.getByRole("button", { name: "MTD" }));
    expect((await screen.findAllByText("Month to date")).length).toBeGreaterThan(0);
  });
});

describe("Cashflow: saved reports", () => {
  it("saves the current view with the page state in the config", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });

    fireEvent.click(screen.getByRole("button", { name: "Saved reports" }));
    fireEvent.change(screen.getByLabelText("Report name"), { target: { value: "My flow" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/saved_reports", expect.objectContaining({
        name: "My flow",
        config: expect.objectContaining({ hash: "section=flow", preset: "1y" }),
      }));
    });
  });

  it("stores the resolved window alongside the preset", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });

    fireEvent.click(screen.getByRole("button", { name: "Saved reports" }));
    fireEvent.change(screen.getByLabelText("Report name"), { target: { value: "My flow" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    const { from, to } = timeframeRange("1y");
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/saved_reports", expect.objectContaining({
        config: expect.objectContaining({ preset: "1y", custom_range: { from, to } }),
      }));
    });
  });

  it("falls back to a report's stored window when its button no longer exists", async () => {
    const base = apiMock.get.getMockImplementation()!;
    apiMock.get.mockImplementation(async (path: string, ...rest: unknown[]) => {
      if (path === "/saved_reports") return [{
        id: "r2", name: "Old FY view", created_at: "2026-08-01T00:00:00Z",
        config: { hash: "section=flow", preset: "c_deleted", custom_range: { from: "2023-10-01", to: "2024-09-30" } },
      }] as never;
      return (base as (p: string, ...r: unknown[]) => Promise<never>)(path, ...rest);
    });
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });

    fireEvent.click(screen.getByRole("button", { name: "Saved reports" }));
    fireEvent.click(await screen.findByText("Old FY view"));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/cashflow/sankey?from=2023-10-01&to=2024-09-30");
    });
    expect(screen.getByRole("button", { name: "Custom" })).toHaveAttribute("aria-pressed", "true");
  });

  it("applying a stored report restores section, mode, and timeframe", async () => {
    renderApp({ initialPath: "/cashflow#section=flow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Money Flow" });
    expect(screen.getByText("$15K")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Saved reports" }));
    fireEvent.click(await screen.findByText("Common flow · 3M"));

    // mode=common from the report's hash → common totals in the ribbon
    expect(await screen.findByText("$9K")).toBeInTheDocument();
    // preset 3m from the config → sankey re-queried with the 3M window
    const { from, to } = timeframeRange("3m");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/sankey?from=${from}&to=${to}`);
    });
  });
});

describe("Cashflow: Transfers section", () => {
  it("renders the review queue and the month-grouped ledger", async () => {
    renderApp({ initialPath: "/cashflow#section=transfers", initialToken: "tok" });

    // Review queue with the pending candidate
    expect(await screen.findByRole("heading", { name: "Needs review (1)" })).toBeInTheDocument();
    expect(screen.getByText(/ACH WITHDRAWAL VANGUARD/)).toBeInTheDocument();
    expect(screen.getByText("$1,200.00")).toBeInTheDocument();
    expect(screen.getByText(/2d apart/)).toBeInTheDocument();

    // Ledger grouped by month, newest first
    expect(await screen.findByRole("heading", { name: "July 2026" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "June 2026" })).toBeInTheDocument();

    // Paired row — account names resolved from /accounts ($500 also appears in
    // the stat ribbon, so allow multiples)
    expect(screen.getAllByText("$500.00").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Everyday Checking").length).toBeGreaterThan(0);
    expect(screen.getAllByText("High-Yield Savings").length).toBeGreaterThan(0);

    // One-sided external row shows the counterparty with an External badge
    expect(screen.getByText("Schwab")).toBeInTheDocument();
    expect(screen.getByText("External", { selector: "span" })).toBeInTheDocument();
    expect(screen.getAllByText("$250.00").length).toBeGreaterThan(0);
  });

  it("shows transfer volume stats in the ribbon", async () => {
    renderApp({ initialPath: "/cashflow#section=transfers", initialToken: "tok" });
    await screen.findByRole("heading", { name: "July 2026" });

    expect(screen.getByText("Moved this month")).toBeInTheDocument();
    expect(screen.getByText("Last month")).toBeInTheDocument();
    expect(screen.getByText("To external · 90d")).toBeInTheDocument();
  });

  it("filters the ledger with the scope tabs", async () => {
    renderApp({ initialPath: "/cashflow#section=transfers", initialToken: "tok" });
    await screen.findByRole("heading", { name: "July 2026" });

    // Assert on row descriptions — account names also appear in the account
    // filter's <option>s, so they can't distinguish ledger contents.
    fireEvent.click(screen.getByRole("tab", { name: "External" }));
    expect(screen.getByText("SCHWAB BROKERAGE XFER")).toBeInTheDocument();
    expect(screen.queryByText("ONLINE TRANSFER TO SAVINGS")).toBeNull();

    fireEvent.click(screen.getByRole("tab", { name: "Internal" }));
    expect(screen.getByText("ONLINE TRANSFER TO SAVINGS")).toBeInTheDocument();
    expect(screen.queryByText("SCHWAB BROKERAGE XFER")).toBeNull();
  });

  it("confirming a candidate POSTs /transfers/:id/confirm", async () => {
    renderApp({ initialPath: "/cashflow#section=transfers", initialToken: "tok" });
    await screen.findByText(/ACH WITHDRAWAL VANGUARD/);

    fireEvent.click(screen.getByRole("button", { name: /Confirm/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers/cand-1/confirm", {});
    });
  });

  it("dismissing a candidate POSTs /transfers/:id/dismiss so the rejection persists", async () => {
    renderApp({ initialPath: "/cashflow#section=transfers", initialToken: "tok" });
    await screen.findByText(/ACH WITHDRAWAL VANGUARD/);

    fireEvent.click(screen.getByTitle("Dismiss"));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers/cand-1/dismiss", {});
    });
  });

  it("unlinking a ledger row confirms first, then DELETEs and refetches", async () => {
    renderApp({ initialPath: "/cashflow#section=transfers", initialToken: "tok" });
    await screen.findByText("ONLINE TRANSFER TO SAVINGS");

    const confirmedGets = () =>
      apiMock.get.mock.calls.filter(([path]) => path === "/transfers?confirmed=true").length;
    const before = confirmedGets();

    fireEvent.click(screen.getAllByRole("button", { name: "Unlink transfer" })[1]);
    // Confirm through the shared dialog
    fireEvent.click(await screen.findByRole("button", { name: "Unlink" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/transfers/tr-1");
      expect(confirmedGets()).toBeGreaterThan(before);
    });
  });

  it("'Scan for transfers' POSTs /transfers/scan", async () => {
    renderApp({ initialPath: "/cashflow#section=transfers", initialToken: "tok" });
    await screen.findByRole("heading", { name: "July 2026" });

    // The scan action now lives in the page-actions dropdown in the header
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /Scan for transfers/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers/scan", {});
    });
  });

  it("shows one empty state and hides the review queue when there is nothing", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/cashflow") return CASHFLOW as never;
      return [] as never;
    });

    renderApp({ initialPath: "/cashflow#section=transfers", initialToken: "tok" });
    expect(await screen.findByText("No transfers yet.")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: /Needs review/ })).toBeNull();
  });
});

describe("Cashflow: section navigation", () => {
  it("switches sections via the sub-nav buttons", async () => {
    renderApp({ initialPath: "/cashflow", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Activity" });

    fireEvent.click(screen.getByRole("button", { name: "Spending" }));
    expect(await screen.findByRole("heading", { name: "Spending" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Activity" })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Transfers" }));
    expect(await screen.findByRole("heading", { name: "Transfers" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Activity" }));
    expect(await screen.findByRole("heading", { name: "Activity" })).toBeInTheDocument();
  });

  it("shows an error message when the cashflow payload fails to load", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/cashflow")) throw new Error("HTTP 500");
      return [] as never;
    });

    // Only the sections that consume the cashflow payload surface its error;
    // the default Activity section fetches its own data and renders regardless.
    renderApp({ initialPath: "/cashflow#section=spending", initialToken: "tok" });
    expect(await screen.findByText("Failed to load cashflow data")).toBeInTheDocument();
  });
});
