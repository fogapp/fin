import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, fireEvent } from "@testing-library/react";
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
import type { SecurityDetail, NewsArticle } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

/** yyyy-mm-dd for `n` days ago — keeps period-cutoff filtering (which uses the
 *  real clock) deterministic no matter when the tests run. */
function daysAgo(n: number): string {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
}

const AAPL_DETAIL: SecurityDetail = {
  id: "sec-aapl",
  ticker: "AAPL",
  name: "Apple Inc",
  security_type: "Stock",
  display_name: "Apple Inc (AAPL)",
  slug: null,
  // All points fall inside the default 6M window: 185 -> 212.44 = +14.83% (+$27.44)
  price_chart: [
    [daysAgo(120), 185, 1_000_000],
    [daysAgo(60), 200, 900_000],
    [daysAgo(1), 212.44, 1_200_000],
  ],
  latest_price: { date: daysAgo(1), close: 212.44 },
  position: {
    as_of_date: daysAgo(1),
    quantity: 100,
    market_value: 21000,
    cost_basis: 15000,
    unrealized_gl: 6000,
    by_account: [{ account: "Brokerage", quantity: 100, market_value: 21000 }],
  },
  dividends: { lifetime: 1200, ytd: 150, last_12mo: 300 },
  overview: {
    sector: "Technology",
    industry: "Consumer Electronics",
    exchange: "NASDAQ",
    country: "USA",
    description: "Designs and sells consumer devices and services.",
    market_cap: 3.2e12,
    pe_ratio: 33.1,
    forward_pe: 30.5,
    eps: 6.42,
    beta: 1.2,
    dividend_yield: 0.0045,
    dividend_per_share: 1.0,
    week_52_high: 240,
    week_52_low: 165,
    analyst_target_price: 250,
    profit_margin: 0.25,
    return_on_equity: 1.5,
    ex_dividend_date: daysAgo(30),
    fetched_at: `${daysAgo(1)}T00:00:00Z`,
  },
  recent_transactions: [
    {
      id: "itx-1", trade_date: "2026-06-15", description: "BOUGHT APPLE INC",
      quantity: 10, price_usd: 205, amount_usd: -2050, cost_usd: 2050,
      income_usd: 0, gl_short_usd: 0, gl_long_usd: 0,
      account_id: "a1", account_name: "Brokerage",
      security_id: "sec-aapl", security_ticker: "AAPL", security_name: "Apple Inc",
      transaction_type: "Buy", transaction_type_category: "buy",
    },
  ],
};


// Candle payload backing the advanced chart + header change math:
// 185 -> 212.44 = +14.83% (+$27.44) over the window.
const AAPL_CANDLES = {
  id: "sec-aapl", ticker: "AAPL", range: "1y", granularity: "1d",
  prev_close: null,
  latest_price: { date: daysAgo(1), close: 212.44 },
  candles: [
    { t: daysAgo(120), o: 184, h: 186, l: 183, c: 185, v: 1_000_000 },
    { t: daysAgo(60), o: 199, h: 201, l: 198, c: 200, v: 900_000 },
    { t: daysAgo(1), o: 211, h: 213, l: 210, c: 212.44, v: 1_200_000 },
  ],
  events: [],
};

const NEWS: NewsArticle[] = [
  {
    title: "Apple unveils new chip lineup",
    url: "https://example.com/apple-chips",
    source: "Reuters",
    published_at: "20260615T133000",
    summary: "The company announced its next generation of silicon.",
    sentiment: "Somewhat_Bullish",
    sentiment_score: 0.31,
  },
  {
    title: "Supply chain concerns weigh on outlook",
    url: "https://example.com/apple-supply",
    source: "Bloomberg",
    published_at: "20260610T090000",
    summary: "Analysts flagged component shortages.",
    sentiment: "Bearish",
    sentiment_score: -0.4,
  },
];

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
    if (path === "/market/AAPL/news") return NEWS as never;
    if (path.startsWith("/market/AAPL/candles")) return AAPL_CANDLES as never;
    if (path === "/market/AAPL") return AAPL_DETAIL as never;
    return [] as never;
  });
});

describe("Security detail: header and stats", () => {
  it("renders name, ticker, latest price and period change", async () => {
    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });

    expect(await screen.findByText("Apple Inc")).toBeInTheDocument();
    expect(screen.getByText("AAPL")).toBeInTheDocument();
    expect(screen.getByText("$212.44")).toBeInTheDocument();
    expect(screen.getByText("+14.83% (+$27.44) 1Y")).toBeInTheDocument();
    expect(screen.getByText(/As of /)).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/market/AAPL");
  });

  it("renders position stats in the stat ribbon", async () => {
    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("Apple Inc");

    expect(screen.getByText("Market Value")).toBeInTheDocument();
    expect(screen.getByText("$21K")).toBeInTheDocument();
    expect(screen.getByText("Cost Basis")).toBeInTheDocument();
    expect(screen.getByText("$15K")).toBeInTheDocument();
    expect(screen.getByText("Unrealized G/L")).toBeInTheDocument();
    expect(screen.getByText("$6K")).toBeInTheDocument();
    expect(screen.getByText("Shares")).toBeInTheDocument();
    expect(screen.getByText("100")).toBeInTheDocument();
    expect(screen.getByText("Dividends (12mo)")).toBeInTheDocument();
    // $300.00 appears in both the stat ribbon and the Dividend Income card
    expect(screen.getAllByText("$300.00").length).toBeGreaterThanOrEqual(1);
  });

  it("shows a staleness badge when the latest price is old, with the source when known", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/market/AAPL/candles")) return AAPL_CANDLES as never;
      if (path === "/market/AAPL") return {
        ...AAPL_DETAIL,
        // The show endpoint carries no age_days — staleness derives from the date.
        latest_price: { date: daysAgo(10), close: 212.44, source: "alpha_vantage" },
      } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("Apple Inc");

    expect(screen.getByText("10d stale")).toBeInTheDocument();
    expect(screen.getByText(/As of .* · USD · Alpha Vantage/)).toBeInTheDocument();
  });

  it("shows no staleness badge for a fresh price", async () => {
    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("Apple Inc");

    expect(screen.queryByText(/stale/)).not.toBeInTheDocument();
  });

  it("recomputes the period change label when another period is selected", async () => {
    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("+14.83% (+$27.44) 1Y");

    fireEvent.click(screen.getByRole("tab", { name: "6M" }));
    expect(await screen.findByText("+14.83% (+$27.44) 6M")).toBeInTheDocument();
  });
});

describe("Security detail: sidebar cards", () => {
  it("renders holdings by account, dividend income, overview and external links", async () => {
    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("Apple Inc");

    // Holdings by account
    expect(screen.getByText("Holdings by Account")).toBeInTheDocument();
    expect(screen.getByText("$21,000.00")).toBeInTheDocument();

    // Dividend income
    expect(screen.getByText("Dividend Income")).toBeInTheDocument();
    expect(screen.getByText("Lifetime")).toBeInTheDocument();
    expect(screen.getByText("$1,200.00")).toBeInTheDocument();

    // Company overview
    expect(screen.getByText("Company Overview")).toBeInTheDocument();
    expect(screen.getByText("Market Cap")).toBeInTheDocument();
    // Market cap renders through the shared formatCurrency compact notation.
    expect(screen.getByText("$3.2T")).toBeInTheDocument();
    expect(screen.getByText("P/E Ratio")).toBeInTheDocument();
    expect(screen.getByText("33.10")).toBeInTheDocument();
    expect(screen.getByText("$165.00 – $240.00")).toBeInTheDocument();
    expect(screen.getByText("Technology · Consumer Electronics")).toBeInTheDocument();

    // External links use the overview exchange
    expect(screen.getByText("View On")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Google Finance/ }))
      .toHaveAttribute("href", "https://www.google.com/finance/quote/AAPL:NASDAQ");
    expect(screen.getByRole("link", { name: /Yahoo Finance/ }))
      .toHaveAttribute("href", "https://finance.yahoo.com/quote/AAPL/");
  });
});

describe("Security detail: tabs", () => {
  it("shows recent transactions in the default tab", async () => {
    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("Apple Inc");

    expect(screen.getByText("buy")).toBeInTheDocument();
    expect(screen.getByText("-$2,050.00")).toBeInTheDocument();
    // Account name appears in both the tx table and the holdings card
    expect(screen.getAllByText("Brokerage").length).toBeGreaterThanOrEqual(1);
  });

  it("fetches and renders news when the News tab is opened", async () => {
    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("Apple Inc");

    fireEvent.click(screen.getByRole("tab", { name: "News" }));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/market/AAPL/news");
    });

    expect(await screen.findByText("Apple unveils new chip lineup")).toBeInTheDocument();
    expect(screen.getByText("Reuters")).toBeInTheDocument();
    expect(screen.getByText(/Jun 15, 2026/)).toBeInTheDocument();
    expect(screen.getByText(/somewhat bullish/)).toBeInTheDocument();
    expect(screen.getByText("Supply chain concerns weigh on outlook")).toBeInTheDocument();
    expect(screen.getByText(/bearish/)).toBeInTheDocument();
  });

  it("shows an empty message when there is no news", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/market/AAPL/news") return [] as never;
      if (path.startsWith("/market/AAPL/candles")) return AAPL_CANDLES as never;
    if (path === "/market/AAPL") return AAPL_DETAIL as never;
      return [] as never;
    });

    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("Apple Inc");

    fireEvent.click(screen.getByRole("tab", { name: "News" }));
    expect(await screen.findByText("No recent news found.")).toBeInTheDocument();
  });
});

describe("Security detail: actions and errors", () => {
  it("POSTs /market/:ticker/refresh when Refresh is clicked", async () => {
    renderApp({ initialPath: "/market/AAPL", initialToken: "tok" });
    await screen.findByText("Apple Inc");

    // "Refresh prices" now lives in the "Page actions" pencil dropdown
    // (menu items render in a portal on document.body).
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /Refresh prices/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/market/AAPL/refresh");
    });
  });

  it("shows 'Security not found' when the detail request fails", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/market/MISSING") throw new Error("HTTP 404");
      return [] as never;
    });

    renderApp({ initialPath: "/market/MISSING", initialToken: "tok" });
    expect(await screen.findByText("Security not found")).toBeInTheDocument();
  });
});
