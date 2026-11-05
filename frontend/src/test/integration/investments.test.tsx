import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, fireEvent } from "@testing-library/react";

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
import type {
  PortfolioData, BuysData, SellsData, DividendsData, CryptoData,
  CostBasisData, BenchmarkMeta, BenchmarkEntry, InvestmentTransaction,
} from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const PORTFOLIO: PortfolioData = {
  as_of_date: "2026-06-30",
  summary: {
    total_value: 250000,
    total_cost_basis: 200000,
    unrealized_gl: 50000,
    est_annual_income: 3200,
  },
  by_asset_class: { Equity: 250000 },
  portfolio_history: {
    "2026-01-02": 210000,
    "2026-03-31": 230000,
    "2026-06-30": 250000,
  },
  positions: [
    {
      id: "p1", security_ticker: "AAPL", security_name: "Apple Inc",
      as_of_date: "2026-06-30", quantity: 100, price: 200,
      market_value: 20000, cost_basis: 15000, unrealized_gl: 5000,
      unrealized_gl_pct: 33.3, asset_class: "Equity",
      est_annual_income: 96, dividend_yield: 0.48,
    },
    {
      id: "p2", security_ticker: "VTI", security_name: "Vanguard Total Market",
      as_of_date: "2026-06-30", quantity: 500, price: 460,
      market_value: 230000, cost_basis: 185000, unrealized_gl: 45000,
      unrealized_gl_pct: 24.3, asset_class: "Equity",
      est_annual_income: 3104, dividend_yield: 1.35,
    },
  ],
};

const BUY_TXN: InvestmentTransaction = {
  id: "it-buy-1", trade_date: "2026-06-15", description: "BUY VANGUARD TOTAL MARKET",
  quantity: 10, price_usd: 460, amount_usd: -4600, cost_usd: 4600,
  income_usd: 0, gl_short_usd: 0, gl_long_usd: 0,
  account_id: "a1", account_name: "Schwab Brokerage",
  security_id: "s-vti", security_ticker: "VTI", security_name: "Vanguard Total Market",
  transaction_type: "BUY", transaction_type_category: "Purchase",
};

const BUYS: BuysData = {
  totals: { all_time: 120000, ytd: 15000, last_12mo: 30000, count: 42, count_12mo: 12, avg: 2857.14 },
  monthly_volume: [["2026-05-01", 5000], ["2026-06-01", 6000]],
  top_securities: [{ ticker: "VTI", name: "Vanguard Total Market", total: 80000, count: 30 }],
  by_account: { "Schwab Brokerage": 120000 },
  cumulative_invested: [["2026-05-01", 114000], ["2026-06-15", 120000]],
  recent: [BUY_TXN],
  transactions: [BUY_TXN],
};

const SELL_TXN: InvestmentTransaction = {
  id: "it-sell-1", trade_date: "2026-04-20", description: "SELL TESLA INC",
  quantity: 25, price_usd: 400, amount_usd: 10000, cost_usd: 0,
  income_usd: 0, gl_short_usd: 500, gl_long_usd: 2500,
  account_id: "a1", account_name: "Schwab Brokerage",
  security_id: "s-tsla", security_ticker: "TSLA", security_name: "Tesla Inc",
  transaction_type: "SELL", transaction_type_category: "Sale",
};

const SELLS: SellsData = {
  totals: {
    proceeds: 40000, proceeds_ytd: 8000, proceeds_12mo: 12000,
    count: 5, count_12mo: 2, avg: 8000,
    realized_short: 500, realized_long: 2500, realized_net: 3000,
  },
  monthly_volume: [["2026-03-01", 30000], ["2026-04-01", 10000]],
  monthly_gl: [["2026-03-01", 1500], ["2026-04-01", 1500]],
  top_securities: [{ ticker: "TSLA", name: "Tesla Inc", total: 25000, count: 2 }],
  by_account: { "Schwab Brokerage": 40000 },
  cumulative_realized: [["2026-03-01", 1500], ["2026-04-20", 3000]],
  recent: [SELL_TXN],
  transactions: [SELL_TXN],
};

const DIV_TXN: InvestmentTransaction = {
  id: "it-div-1", trade_date: "2026-06-10", description: "DIVIDEND SCHD",
  quantity: 0, price_usd: 0, amount_usd: 250, cost_usd: 0,
  income_usd: 250, gl_short_usd: 0, gl_long_usd: 0,
  account_id: "a1", account_name: "Schwab Brokerage",
  security_id: "s-schd", security_ticker: "SCHD", security_name: "Schwab Dividend ETF",
  transaction_type: "DIVIDEND", transaction_type_category: "Dividend",
};

const DIVIDENDS: DividendsData = {
  totals: { lifetime: 6000, ytd: 900, last_12mo: 1800, count: 24, count_12mo: 8, avg: 250 },
  monthly_dividends: [["2026-05-01", 150], ["2026-06-01", 250]],
  top_securities: [{ ticker: "SCHD", name: "Schwab Dividend ETF", total: 3000, count: 12 }],
  by_account: { "Schwab Brokerage": 6000 },
  cumulative_dividends: [["2026-05-01", 5750], ["2026-06-10", 6000]],
  recent: [DIV_TXN],
  transactions: [DIV_TXN],
};

const CRYPTO_TXN: InvestmentTransaction = {
  id: "it-btc-1", trade_date: "2026-06-01", description: "BUY BITCOIN",
  quantity: 0.1, price_usd: 50000, amount_usd: -5000, cost_usd: 5000,
  income_usd: 0, gl_short_usd: 0, gl_long_usd: 0,
  account_id: "a2", account_name: "Coinbase",
  security_id: "s-btc", security_ticker: "BTC", security_name: "Bitcoin",
  transaction_type: "BUY", transaction_type_category: "Purchase",
};

const CRYPTO: CryptoData = {
  summary: {
    total_value: 30000, total_cost: 20000, unrealized_gl: 10000,
    total_invested: 20000, buy_count: 15, ytd_invested: 4000,
  },
  positions: [
    {
      id: "cp1", ticker: "BTC", name: "Bitcoin", quantity: 0.5, price: 50000,
      market_value: 25000, cost_basis: 16000, unrealized_gl: 9000, unrealized_gl_pct: 56.25,
    },
    {
      id: "cp2", ticker: "ETH", name: "Ethereum", quantity: 2, price: 2500,
      market_value: 5000, cost_basis: 4000, unrealized_gl: 1000, unrealized_gl_pct: 25,
    },
  ],
  balance_history: { "2026-01-02": 22000, "2026-06-30": 30000 },
  monthly_volume: [["2026-05-01", 2000], ["2026-06-01", 5000]],
  cumulative_invested: [["2026-05-01", 15000], ["2026-06-01", 20000]],
  top_assets: [{ ticker: "BTC", name: "Bitcoin", total: 16000, count: 10 }],
  by_account: { Coinbase: 20000 },
  recent: [CRYPTO_TXN],
};

const COST_BASIS: CostBasisData = {
  summary: {
    total_positions: 2, complete: 1, partial: 1, unknown: 0,
    total_value: 250000, known_cost_basis: 185000,
  },
  positions: [
    {
      security_id: "sec-aapl", ticker: "AAPL", name: "Apple Inc",
      current_quantity: 100, current_value: 20000, asset_class: "Equity",
      bought_quantity: 100, sold_quantity: 0, net_quantity: 100, gap_quantity: 0,
      computed_cost_basis: 15000, avg_cost_per_share: 150, unrealized_gl: 5000,
      status: "complete", transaction_count: 4, earliest_transaction: "2024-01-05",
      lots: [],
    },
    {
      security_id: "sec-msft", ticker: "MSFT", name: "Microsoft Corp",
      current_quantity: 80, current_value: 36000, asset_class: "Equity",
      bought_quantity: 50, sold_quantity: 0, net_quantity: 50, gap_quantity: 30,
      computed_cost_basis: 10000, avg_cost_per_share: 200, unrealized_gl: null,
      status: "partial", transaction_count: 2, earliest_transaction: "2025-02-10",
      lots: [],
    },
  ],
};

const BENCHMARKS: BenchmarkMeta[] = [{ symbol: "SPY", label: "S&P 500" }];

const BENCHMARK_SPY: BenchmarkEntry = {
  symbol: "SPY",
  label: "S&P 500",
  prices: [["2026-01-02", 470], ["2026-03-31", 495], ["2026-06-30", 520]],
  syncing: false,
};

function mockInvestmentRoutes(overrides: Record<string, unknown> = {}) {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path in overrides) return overrides[path] as never;
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/portfolio") return PORTFOLIO as never;
    if (path === "/buys") return BUYS as never;
    // PortfolioSection requests the summary variant (?limit=1) of both.
    if (path === "/sells" || path === "/sells?limit=1") return SELLS as never;
    if (path === "/dividends" || path === "/dividends?limit=1") return DIVIDENDS as never;
    if (path === "/investment_transactions?limit=all") return [BUY_TXN, SELL_TXN, DIV_TXN] as never;
    if (path === "/crypto") return CRYPTO as never;
    if (path === "/cost_basis") return COST_BASIS as never;
    if (path === "/benchmarks") return BENCHMARKS as never;
    if (path === "/benchmarks/SPY") return BENCHMARK_SPY as never;
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

  mockInvestmentRoutes();
});

describe("Investments: portfolio (default section)", () => {
  it("renders the summary ribbon and holdings from /portfolio", async () => {
    renderApp({ initialPath: "/investments", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Portfolio" })).toBeInTheDocument();
    expect(screen.getByText(/as of/i)).toBeInTheDocument();

    // Stat ribbon (compact currency)
    expect(screen.getByText("$250K")).toBeInTheDocument();     // total value
    expect(screen.getByText("$200K")).toBeInTheDocument();     // cost basis
    expect(screen.getByText("$50K")).toBeInTheDocument();      // unrealized G/L
    expect(screen.getByText("$3,200.00")).toBeInTheDocument(); // est. annual income

    // Holdings table rows
    expect(screen.getByText("AAPL")).toBeInTheDocument();
    expect(screen.getByText("Apple Inc")).toBeInTheDocument();
    expect(screen.getByText("VTI")).toBeInTheDocument();

    expect(apiMock.get).toHaveBeenCalledWith("/portfolio");
  });
});

describe("Investments: section switching", () => {
  it("switches to Buys via the sidebar nav and fetches /buys", async () => {
    renderApp({ initialPath: "/investments", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Portfolio" });
    expect(apiMock.get).not.toHaveBeenCalledWith("/buys");

    fireEvent.click(screen.getByRole("button", { name: "Buys" }));

    expect(await screen.findByRole("heading", { name: "Buys" })).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/buys");
    expect(screen.queryByRole("heading", { name: "Portfolio" })).not.toBeInTheDocument();
  });

  it("redirects the retired #section=performance deep link to Portfolio", async () => {
    renderApp({ initialPath: "/investments#section=performance", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Portfolio" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Performance" })).not.toBeInTheDocument();
  });

  it("deep-links to a section via the #section hash param", async () => {
    renderApp({ initialPath: "/investments#section=crypto", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Crypto" })).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/crypto");
    expect(apiMock.get).not.toHaveBeenCalledWith("/portfolio");
  });
});

describe("Investments: buys section", () => {
  it("renders totals, top securities, by-account and recent transactions", async () => {
    renderApp({ initialPath: "/investments#section=buys", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Buys" })).toBeInTheDocument();

    // Stat ribbon
    expect(screen.getByText("$120K")).toBeInTheDocument();     // all-time invested
    expect(screen.getByText("$15K")).toBeInTheDocument();      // YTD
    expect(screen.getByText("$30K")).toBeInTheDocument();      // last 12mo
    expect(screen.getByText("42")).toBeInTheDocument();        // transaction count
    expect(screen.getByText("$2,857.14")).toBeInTheDocument(); // avg size

    // Top securities sidebar
    expect(screen.getByText("Top Securities")).toBeInTheDocument();
    expect(screen.getByText("$80,000.00")).toBeInTheDocument();

    // By account sidebar
    expect(screen.getByText("By Account")).toBeInTheDocument();
    expect(screen.getByText("$120,000.00")).toBeInTheDocument();

    // Transaction table row + top-securities entry both show the ticker
    expect(screen.getAllByText("VTI").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("Purchase")).toBeInTheDocument();
  });
});

describe("Investments: transactions section", () => {
  it("lists every investment transaction across accounts", async () => {
    renderApp({ initialPath: "/investments#section=transactions", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Transactions" })).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/investment_transactions?limit=all");
    expect(screen.getByText("3 investment transactions across all accounts")).toBeInTheDocument();

    // One row per kind, all in a single table.
    expect(screen.getByText("VTI")).toBeInTheDocument();
    expect(screen.getByText("TSLA")).toBeInTheDocument();
    expect(screen.getByText("SCHD")).toBeInTheDocument();
  });
});

describe("Investments: sells section", () => {
  it("renders proceeds and realized gain/loss totals", async () => {
    renderApp({ initialPath: "/investments#section=sells", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Sells" })).toBeInTheDocument();

    expect(screen.getByText("$40K")).toBeInTheDocument();      // total proceeds
    expect(screen.getByText("$8K")).toBeInTheDocument();       // YTD proceeds
    expect(screen.getByText("$3K")).toBeInTheDocument();       // realized net
    expect(screen.getByText("$500.00")).toBeInTheDocument();   // short-term G/L
    expect(screen.getByText("$2,500.00")).toBeInTheDocument(); // long-term G/L

    // Top securities + transaction row
    expect(screen.getAllByText("TSLA").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("$25,000.00")).toBeInTheDocument();
  });
});

describe("Investments: dividends section", () => {
  it("renders dividend totals and top securities", async () => {
    renderApp({ initialPath: "/investments#section=dividends", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Dividends" })).toBeInTheDocument();

    expect(screen.getByText("$6K")).toBeInTheDocument();     // lifetime
    expect(screen.getByText("$900")).toBeInTheDocument();    // YTD (compact)
    expect(screen.getByText("$1.8K")).toBeInTheDocument();   // last 12mo
    expect(screen.getByText("24")).toBeInTheDocument();      // count
    // Avg payment in the ribbon + the $250 dividend row in the table
    expect(screen.getAllByText("$250.00").length).toBeGreaterThanOrEqual(2);

    expect(screen.getAllByText("SCHD").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("$3,000.00")).toBeInTheDocument(); // SCHD total dividends
  });

  it("hides the Top Securities and By Account cards when the payload has none", async () => {
    mockInvestmentRoutes({
      "/dividends": { ...DIVIDENDS, top_securities: [], by_account: {} },
    });

    renderApp({ initialPath: "/investments#section=dividends", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Dividends" })).toBeInTheDocument();
    expect(screen.queryByText("Top Securities")).not.toBeInTheDocument();
    expect(screen.queryByText("By Account")).not.toBeInTheDocument();
  });
});

describe("Investments: timeframe", () => {
  /** Serve windowed /dividends requests too ("?from=…&to=…"). */
  function withWindowedDividends(prefs: Record<string, unknown> = {}) {
    const base = apiMock.get.getMockImplementation()!;
    apiMock.get.mockImplementation(async (path: string, ...rest: unknown[]) => {
      if (path === "/preferences") return { data: prefs } as never;
      if (path.startsWith("/dividends?from=")) return DIVIDENDS as never;
      return (base as (p: string, ...r: unknown[]) => Promise<never>)(path, ...rest);
    });
  }

  it("offers the shared row, opens on All, and names the period stat after the window", async () => {
    withWindowedDividends();
    renderApp({ initialPath: "/investments#section=dividends", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dividends" });

    expect(screen.getByRole("button", { name: "All" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByText("Last 12mo")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "MTD" }));
    const { from, to } = timeframeRange("mtd");
    await waitFor(() => expect(apiMock.get).toHaveBeenCalledWith(`/dividends?from=${from}&to=${to}`));
    expect(await screen.findByText("Month to date")).toBeInTheDocument();
  });

  it("opens on the default chosen for Investments in Settings", async () => {
    withWindowedDividends({ timeframes: { defaults: { investments: "ytd" } } });
    renderApp({ initialPath: "/investments#section=dividends", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Dividends" });

    const { from, to } = timeframeRange("ytd");
    await waitFor(() => expect(apiMock.get).toHaveBeenCalledWith(`/dividends?from=${from}&to=${to}`));
    expect(screen.getByRole("button", { name: "YTD" })).toHaveAttribute("aria-pressed", "true");
  });
});

describe("Investments: crypto section", () => {
  it("renders summary, positions, top assets and by-account", async () => {
    renderApp({ initialPath: "/investments#section=crypto", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Crypto" })).toBeInTheDocument();
    expect(screen.getByText("2 assets")).toBeInTheDocument();

    // Stat ribbon
    expect(screen.getByText("$30K")).toBeInTheDocument(); // total value
    expect(screen.getByText("$10K")).toBeInTheDocument(); // unrealized G/L
    expect(screen.getByText("$20K")).toBeInTheDocument(); // total invested
    expect(screen.getByText("$4K")).toBeInTheDocument();  // YTD invested

    // Positions (holdings table) — BTC also appears in Top Assets and the txn table
    expect(screen.getAllByText("BTC").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("ETH")).toBeInTheDocument();
    expect(screen.getByText("Ethereum")).toBeInTheDocument();

    // Top assets + by account sidebars
    expect(screen.getByText("Top Assets")).toBeInTheDocument();
    // BTC cost basis in the holdings table + total invested in Top Assets
    expect(screen.getAllByText("$16,000.00").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("By Account")).toBeInTheDocument();
    expect(screen.getByText("$20,000.00")).toBeInTheDocument();
  });

  it("omits the holdings table and asset count when there are no positions", async () => {
    mockInvestmentRoutes({
      "/crypto": { ...CRYPTO, positions: [], top_assets: [], by_account: {}, recent: [] },
    });

    renderApp({ initialPath: "/investments#section=crypto", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Crypto" })).toBeInTheDocument();
    expect(screen.queryByText(/assets?$/)).not.toBeInTheDocument();
    expect(screen.queryByText("BTC")).not.toBeInTheDocument();
    expect(screen.getByText("No investment transactions")).toBeInTheDocument();
  });
});

describe("Investments: cost basis section", () => {
  it("renders summary counts, filter tabs, positions and status badges", async () => {
    renderApp({ initialPath: "/investments#section=cost_basis", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Cost Basis" })).toBeInTheDocument();

    // Ribbon
    expect(screen.getByText("$185K")).toBeInTheDocument(); // known cost basis

    // Filter tabs carry the summary counts (label + count span concatenate
    // in the accessible name: "All2")
    expect(screen.getByRole("tab", { name: "All2" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Complete1" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Gaps1" })).toBeInTheDocument();

    // Position rows
    expect(screen.getByText("AAPL")).toBeInTheDocument();
    expect(screen.getByText("MSFT")).toBeInTheDocument();
    // "Complete" appears both as a ribbon stat label and as AAPL's status badge
    expect(screen.getAllByText("Complete").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("Partial")).toBeInTheDocument();
    expect(screen.getByText("$15,000.00")).toBeInTheDocument(); // AAPL computed cost basis
  });

  it("filters positions when a status tab is clicked", async () => {
    renderApp({ initialPath: "/investments#section=cost_basis", initialToken: "tok" });
    await screen.findByText("MSFT");

    fireEvent.click(screen.getByRole("tab", { name: "Complete1" }));

    expect(screen.getByText("AAPL")).toBeInTheDocument();
    expect(screen.queryByText("MSFT")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("tab", { name: "Gaps1" }));

    expect(screen.getByText("MSFT")).toBeInTheDocument();
    expect(screen.queryByText("AAPL")).not.toBeInTheDocument();
  });

  it("shows an empty state when there are no positions", async () => {
    mockInvestmentRoutes({
      "/cost_basis": {
        summary: { total_positions: 0, complete: 0, partial: 0, unknown: 0, total_value: 0, known_cost_basis: 0 },
        positions: [],
      },
    });

    renderApp({ initialPath: "/investments#section=cost_basis", initialToken: "tok" });

    expect(await screen.findByText("No positions found")).toBeInTheDocument();
  });
});

describe("Investments: portfolio performance", () => {
  it("renders total return, realized G/L and dividend income summaries", async () => {
    renderApp({ initialPath: "/investments", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Portfolio" })).toBeInTheDocument();

    // Total return = unrealized 50,000 + realized net 3,000 + dividends 6,000
    // = 59,000 on a 200,000 cost basis → +29.5%
    expect(screen.getByText("$59K (+29.5%)")).toBeInTheDocument();
    expect(screen.getByText("$50K")).toBeInTheDocument(); // unrealized G/L
    expect(screen.getByText("$3K")).toBeInTheDocument();  // realized G/L
    expect(screen.getByText("$6K")).toBeInTheDocument();  // dividends

    // Realized G/L sidebar table
    expect(screen.getByText("Short-term")).toBeInTheDocument();
    expect(screen.getByText("+$500.00")).toBeInTheDocument();
    expect(screen.getByText("+$2,500.00")).toBeInTheDocument();
    expect(screen.getByText("+$3,000.00")).toBeInTheDocument();

    // Dividend income sidebar table
    expect(screen.getByText("$900.00")).toBeInTheDocument();
    expect(screen.getByText("$1,800.00")).toBeInTheDocument();
    expect(screen.getByText("$6,000.00")).toBeInTheDocument();

    // Holdings table
    expect(screen.getByText("AAPL")).toBeInTheDocument();
    expect(screen.getByText("VTI")).toBeInTheDocument();

    expect(apiMock.get).toHaveBeenCalledWith("/benchmarks");
  });

  it("adds a benchmark comparison and fetches its prices", async () => {
    renderApp({ initialPath: "/investments", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Portfolio" });

    const input = await screen.findByPlaceholderText("Compare…");
    fireEvent.focus(input);

    // Inline spans concatenate in the accessible name: "SPYS&P 500"
    fireEvent.click(await screen.findByRole("button", { name: /SPY.*S&P 500/ }));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/benchmarks/SPY");
    });

    // Compare mode swaps in the % return chart and shows the selected chip
    expect(screen.getByText("% Return vs Benchmark")).toBeInTheDocument();
    expect(screen.getByText("SPY")).toBeInTheDocument();
  });
});
