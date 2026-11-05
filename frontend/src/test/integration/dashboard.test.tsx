import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, fireEvent, waitFor } from "@testing-library/react";

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
import type { DashboardData } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

// fillLastMonths keys off the real current date, so anchor chart data there.
const now = new Date();
const CUR_MONTH = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;

const DASHBOARD: DashboardData = {
  stats: {
    portfolio_value: 250000,
    unrealized: 40000,
    cost_basis: 210000,
    transactions: 1234,
    income_ytd: 3200,
  },
  compact_stats: {
    spend: 2345.67, spend_change: 12.5,
    income: 8000, income_change: -4.2,
    cc_count: 42, cc_count_change: null,
    cc_avg: 55.85, cc_avg_change: null,
  },
  portfolio_chart: { "2026-06-01": 240000, "2026-06-15": 245000, "2026-07-01": 250000 },
  allocation: { "US Equity": 150000, Bonds: 100000 },
  income_series: { [CUR_MONTH]: 320 },
  monthly_spend: { [CUR_MONTH]: 2345.67 },
  activity_chart: [],
  recent_transactions: [],
};

// Payload for a cash-only user: no investment data at all.
const CASH_ONLY_DASHBOARD: DashboardData = {
  ...DASHBOARD,
  stats: { ...DASHBOARD.stats, portfolio_value: 0, unrealized: 0, cost_basis: 0 },
  portfolio_chart: {},
  allocation: {},
  income_series: {},
};

const TXNS = [
  {
    id: "tx-1", transaction_date: "2026-06-20", description: "STARBUCKS RESERVE",
    amount: -7.25, source: "credit_card", transaction_type: "Sale",
    merchant_id: "m1", merchant_name: "Starbucks",
    category_id: "c1", category_name: "Coffee",
    account_id: "a1", account_name: "Amex",
    created_at: "2026-06-20T10:00:00Z",
    tags: [], memo: null,
  },
  {
    id: "tx-2", transaction_date: "2026-06-21", description: "WALMART",
    amount: -42.0, source: "credit_card", transaction_type: "Sale",
    merchant_id: null, merchant_name: null,
    category_id: null, category_name: null,
    account_id: "a1", account_name: "Amex",
    created_at: "2026-06-21T10:00:00Z",
    tags: [], memo: null,
  },
];

// A populated /net_worth payload for the Net Worth widget.
const NET_WORTH = {
  range: "1y",
  series: [
    { date: "2026-06-01", net: 490000 },
    { date: "2026-07-01", net: 500000 },
  ],
  stats: { net_worth: 500000, changes: { "1m": { amount: 10000, pct: 2 } } },
};

function mockGets(dashboard: DashboardData, extra: Record<string, unknown> = {}, prefs: Record<string, unknown> = {}) {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: prefs } as never;
    if (path.startsWith("/dashboard")) return dashboard as never;
    if (path.startsWith("/cash_transactions")) return TXNS as never;
    for (const [prefix, payload] of Object.entries(extra)) {
      if (path.startsWith(prefix)) return payload as never;
    }
    return [] as never;
  });
}

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
  mockGets(DASHBOARD);
});

describe("Dashboard: stat ribbon", () => {
  it("renders MTD spend/income, CC stats and txn count from the payload", async () => {
    renderApp({ initialPath: "/", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();

    expect(screen.getByText("MTD Spend")).toBeInTheDocument();
    expect(screen.getByText("$2,345.67")).toBeInTheDocument();
    expect(screen.getByText("MTD Income")).toBeInTheDocument();
    expect(screen.getByText("$8,000.00")).toBeInTheDocument();
    expect(screen.getByText("CC Txns")).toBeInTheDocument();
    expect(screen.getByText("42")).toBeInTheDocument();
    expect(screen.getByText("$55.85")).toBeInTheDocument(); // Avg Txn
    expect(screen.getByText("1,234")).toBeInTheDocument();  // total Txns
  });

  it("shows net worth and portfolio stats when investment data exists", async () => {
    mockGets(DASHBOARD, { "/net_worth": NET_WORTH });
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    // Ribbon item and sidebar widget read the same query, so they agree.
    await waitFor(() => expect(screen.getAllByText("Net Worth")).toHaveLength(2));
    expect(screen.getAllByText("$500K")).toHaveLength(2);
    expect(screen.getAllByRole("link", { name: /Net Worth/ })[0]).toHaveAttribute("href", "/net-worth");
    expect(screen.getByText("Portfolio")).toBeInTheDocument();
    expect(screen.getByText("$250K")).toBeInTheDocument();
    expect(screen.getByText("Unrealized")).toBeInTheDocument();
    expect(screen.getByText("$40K")).toBeInTheDocument();
    expect(screen.getByText("Cost Basis")).toBeInTheDocument();
    expect(screen.getByText("$210K")).toBeInTheDocument();
    expect(screen.getByText("YTD Income")).toBeInTheDocument();
    expect(screen.getByText("$3.2K")).toBeInTheDocument();
    expect(screen.queryByText("YTD Cashflow")).not.toBeInTheDocument();
  });
});

describe("Dashboard: conditional charts", () => {
  it("shows portfolio and allocation charts when investment data exists", async () => {
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    expect(screen.getByText("Portfolio Value")).toBeInTheDocument();
    expect(screen.getByText("Allocation")).toBeInTheDocument();
    expect(screen.getByText("Monthly Spend")).toBeInTheDocument();
  });

  it("hides investment charts and stats for a cash-only user", async () => {
    mockGets(CASH_ONLY_DASHBOARD);
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    // Monthly Spend always renders; everything investment-flavoured does not.
    expect(screen.getByText("Monthly Spend")).toBeInTheDocument();
    expect(screen.queryByText("Portfolio Value")).not.toBeInTheDocument();
    expect(screen.queryByText("Allocation")).not.toBeInTheDocument();
    expect(screen.queryByText("Investment Income")).not.toBeInTheDocument();
    expect(screen.queryByText("Portfolio")).not.toBeInTheDocument();
    expect(screen.queryByText("Net Worth")).not.toBeInTheDocument();
    expect(screen.queryByText("Unrealized")).not.toBeInTheDocument();
  });
});

describe("Dashboard: configurable insights", () => {
  it("renders default data-backed widgets when their endpoints return data", async () => {
    mockGets(DASHBOARD, { "/net_worth": NET_WORTH });
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    // The widget, plus the ribbon's Net Worth item reading the same query.
    await waitFor(() => expect(screen.getAllByText("Net Worth")).toHaveLength(2));
    expect(screen.getAllByText("$500K")).toHaveLength(2);
  });

  it("hides default widgets whose endpoints have no data", async () => {
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    expect(screen.queryByText("Net Worth")).not.toBeInTheDocument();
    expect(screen.queryByText("Upcoming Bills")).not.toBeInTheDocument();
    expect(screen.queryByText("Budget")).not.toBeInTheDocument();
  });

  it("renders only the widgets saved in preferences", async () => {
    mockGets(DASHBOARD, {}, { dashboard: { widgets: ["monthly_spend"] } });
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    expect(screen.getByText("Monthly Spend")).toBeInTheDocument();
    expect(screen.queryByText("Portfolio Value")).not.toBeInTheDocument();
    expect(screen.queryByText("Allocation")).not.toBeInTheDocument();
  });

  it("shows an empty state for a hand-picked widget with no data", async () => {
    mockGets(CASH_ONLY_DASHBOARD, {}, { dashboard: { widgets: ["portfolio_value"] } });
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    expect(screen.getByText("Portfolio Value")).toBeInTheDocument();
    expect(screen.getByText("No portfolio history")).toBeInTheDocument();
  });

  it("updates the sidebar when the selection changes in the customize dialog", async () => {
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });
    expect(screen.getByText("Monthly Spend")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Customize insights" }));
    expect(await screen.findByText("Customize insights")).toBeInTheDocument();

    // Uncheck Monthly Spend (shown) and save.
    fireEvent.click(screen.getByRole("checkbox", { name: "Monthly Spend" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(screen.queryByText("Monthly Spend")).not.toBeInTheDocument();
    // The saved (customized) selection flips empty widgets to honest empty states.
    expect(await screen.findByText("Upcoming Bills")).toBeInTheDocument();
  });

  it("previews a widget in the customize dialog when its row is clicked", async () => {
    mockGets(DASHBOARD, { "/net_worth": NET_WORTH });
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });
    // The sidebar widget and the ribbon's Net Worth item.
    await waitFor(() => expect(screen.getAllByText("$500K")).toHaveLength(2));

    fireEvent.click(screen.getByRole("button", { name: "Customize insights" }));
    expect(await screen.findByText("Select an insight to see a live preview of it here.")).toBeInTheDocument();

    // Clicking the row label renders the live widget a second time, in the pane.
    fireEvent.click(screen.getByRole("button", { name: /one-year trend/ }));
    await waitFor(() => expect(screen.getAllByText("$500K")).toHaveLength(3));
  });

  it("previews an unselected widget before it is added", async () => {
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    fireEvent.click(screen.getByRole("button", { name: "Customize insights" }));
    // Markets isn't in the default selection and its endpoint has no data, so
    // the preview shows its honest empty state.
    fireEvent.click(await screen.findByRole("button", { name: /biggest movers/ }));
    expect(await screen.findByText("No market data")).toBeInTheDocument();
  });
});

describe("Dashboard: recent activity", () => {
  it("renders recent transactions from /cash_transactions", async () => {
    renderApp({ initialPath: "/", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dashboard" });

    expect(screen.getByText("Recent Activity")).toBeInTheDocument();
    expect(await screen.findByText("Starbucks")).toBeInTheDocument();
    expect(screen.getByText("WALMART")).toBeInTheDocument();
  });
});

describe("Dashboard: empty and error states", () => {
  it("shows the welcome screen with import cards when there are no transactions", async () => {
    mockGets({ ...CASH_ONLY_DASHBOARD, stats: { ...CASH_ONLY_DASHBOARD.stats, transactions: 0 } });
    renderApp({ initialPath: "/", initialToken: "tok" });

    expect(await screen.findByText("Welcome to Fin")).toBeInTheDocument();
    expect(screen.getByText("No transactions yet. Add data to get started.")).toBeInTheDocument();
    expect(screen.getByText("Import a CSV")).toBeInTheDocument();
    expect(screen.getByText("Connect via Plaid")).toBeInTheDocument();
    expect(screen.getByText("Set up workflows")).toBeInTheDocument();
    expect(screen.getByText("Watch securities")).toBeInTheDocument();
  });

  it("keeps the header's account menu (and its Settings link) on the welcome screen", async () => {
    mockGets({ ...CASH_ONLY_DASHBOARD, stats: { ...CASH_ONLY_DASHBOARD.stats, transactions: 0 } });
    renderApp({ initialPath: "/", initialToken: "tok" });

    expect(await screen.findByText("Welcome to Fin")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Dashboard" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Account menu" })).toBeInTheDocument();
  });

  it("navigates to /accounts when the 'Import a CSV' card is clicked", async () => {
    mockGets({ ...CASH_ONLY_DASHBOARD, stats: { ...CASH_ONLY_DASHBOARD.stats, transactions: 0 } });
    renderApp({ initialPath: "/", initialToken: "tok" });

    fireEvent.click(await screen.findByText("Import a CSV"));

    expect(await screen.findByPlaceholderText("Search accounts…")).toBeInTheDocument();
  });

  it("shows an error state when /dashboard fails", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/dashboard")) throw new Error("HTTP 500");
      return [] as never;
    });

    renderApp({ initialPath: "/", initialToken: "tok" });
    expect(await screen.findByText("Failed to load dashboard")).toBeInTheDocument();
    expect(screen.getByText("HTTP 500")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Account menu" })).toBeInTheDocument();
  });
});
