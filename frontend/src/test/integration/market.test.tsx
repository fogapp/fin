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
import type { SecuritySummary, SecurityDetail } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const SECURITIES: SecuritySummary[] = [
  // Held only — must never appear in the watchlist-only list.
  {
    id: "sec-aapl", ticker: "AAPL", name: "Apple Inc", security_type: "Stock",
    instrument_class: "equity", display_name: "Apple Inc (AAPL)",
    latest_price: { date: "2026-07-01", close: 212.44, source: "alpha_vantage", age_days: 0 },
    ytd_change_pct: 12.34, day_change_pct: 0.85, spark: [210, 211, 212.44], market_value: 25000, watched: false,
  },
  {
    id: "sec-vti", ticker: "VTI", name: "Vanguard Total Stock Market ETF", security_type: "ETF",
    instrument_class: "etf", display_name: "Vanguard Total Stock Market ETF (VTI)",
    latest_price: { date: "2026-07-01", close: 305.1, source: "alpha_vantage", age_days: 1 },
    ytd_change_pct: 6.78, day_change_pct: 0.4, spark: [303, 304, 305.1], market_value: 52000, watched: false,
  },
  // Watched, not held — shows in the list.
  {
    id: "sec-nvda", ticker: "NVDA", name: "NVIDIA Corp", security_type: "Stock",
    instrument_class: "equity", display_name: "NVIDIA Corp (NVDA)",
    // A 3-day-old EOD price is normal over a weekend — must NOT badge.
    latest_price: { date: "2026-06-28", close: 158.11, source: "alpha_vantage", age_days: 3 },
    ytd_change_pct: -8.4, day_change_pct: -3.21, spark: [165, 160, 158.11], market_value: 0, watched: true,
  },
  // Known but neither held nor watched — only surfaced as an "add" suggestion.
  {
    id: "sec-tsla", ticker: "TSLA", name: "Tesla Inc", security_type: "Stock",
    instrument_class: "equity", display_name: "Tesla Inc (TSLA)",
    latest_price: { date: "2026-07-01", close: 244.4, source: "alpha_vantage", age_days: 0 },
    ytd_change_pct: null, day_change_pct: null, spark: [], market_value: 0, watched: false,
  },
  // Held crypto — must never appear in the watchlist-only list.
  {
    id: "sec-btc", ticker: "BTC", name: "Bitcoin", security_type: "Crypto",
    instrument_class: "crypto", display_name: "Bitcoin (BTC)",
    latest_price: { date: "2026-06-27", close: 101000, source: "coin_market_cap", age_days: 6 },
    ytd_change_pct: 22.5, day_change_pct: 1.2, spark: [99000, 100000, 101000], market_value: 18000, watched: false,
  },
  // Watched *and* held — the watchlist is about the watch flag alone, so it
  // must list even though there's a position behind it.
  {
    id: "sec-coin", ticker: "COIN", name: "Coinbase Global Inc", security_type: "Stock",
    instrument_class: "equity", display_name: "Coinbase Global Inc (COIN)",
    latest_price: { date: "2026-07-01", close: 288.2, source: "alpha_vantage", age_days: 0 },
    ytd_change_pct: 4.2, day_change_pct: 1.1, spark: [280, 285, 288.2], market_value: 9100, watched: true,
  },
  // Watched crypto with a badly stale price (10+ days) → red badge.
  {
    id: "sec-doge", ticker: "DOGE", name: "Dogecoin", security_type: "Crypto",
    instrument_class: "crypto", display_name: "Dogecoin (DOGE)",
    latest_price: { date: "2026-06-21", close: 0.31, source: "coin_gecko", age_days: 12 },
    ytd_change_pct: -12.5, day_change_pct: -0.9, spark: [0.33, 0.32, 0.31], market_value: 0, watched: true,
  },
  // Watched crypto with a moderately stale price (past the 5-day weekend
  // allowance) → amber badge.
  {
    id: "sec-eth", ticker: "ETH", name: "Ethereum", security_type: "Crypto",
    instrument_class: "crypto", display_name: "Ethereum (ETH)",
    latest_price: { date: "2026-06-27", close: 3400, source: "coin_market_cap", age_days: 6 },
    ytd_change_pct: 9.1, day_change_pct: 2.1, spark: [3300, 3350, 3400], market_value: 0, watched: true,
  },
];

// Overview-pane payload: one index, one gainer, one news item.
const MARKET_SUMMARY = {
  as_of: "2026-07-01",
  indices: [
    { symbol: "SPY", label: "S&P 500", close: 505, date: "2026-07-01", day_change_pct: 1.0, spark: [500, 502, 505] },
  ],
  // Tickers deliberately absent from the watchlist fixtures so list-row
  // queries (getByText("NVDA")) stay unambiguous.
  movers: {
    gainers: [
      { id: "sec-amd", param: "AMD", ticker: "AMD", name: "Advanced Micro Devices", display_name: "Advanced Micro Devices (AMD)",
        instrument_class: "equity", close: 190, day_change_pct: 2.1, spark: [180, 185, 190] },
    ],
    losers: [],
  },
  news: [
    { ticker: "AMD", param: "AMD", title: "NVIDIA announces the next thing", url: "https://news.example.com/nvda",
      source: "Newswire", published_at: "20260701T120000", summary: "Chips.", sentiment: "Bullish", sentiment_score: 0.4 },
  ],
};

const EMPTY_PORTFOLIO = {
  as_of_date: null,
  summary: { total_value: 0, total_cost_basis: 0, unrealized_gl: 0, est_annual_income: 0 },
  by_asset_class: {}, portfolio_history: {}, positions: [],
};

// Lean detail payload for the inline detail pane (no position/overview).
const NVDA_DETAIL: SecurityDetail = {
  id: "sec-nvda", ticker: "NVDA", name: "NVIDIA Corp", security_type: "Stock",
  instrument_class: "equity", display_name: "NVIDIA Corp (NVDA)", slug: null, watched: false,
  price_chart: [],
  latest_price: { date: "2026-06-28", close: 158.11 },
  position: null,
  dividends: { lifetime: 0, ytd: 0, last_12mo: 0 },
  overview: null,
  recent_transactions: [],
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
    if (path === "/market") return SECURITIES as never;
    if (path === "/market/summary") return MARKET_SUMMARY as never;
    if (path === "/portfolio") return EMPTY_PORTFOLIO as never;
    if (path === "/market/NVDA") return NVDA_DETAIL as never;
    return [] as never;
  });
});

describe("Market: list", () => {
  it("renders only the watchlist, with no holdings and no instrument-class grouping", async () => {
    renderApp({ initialPath: "/market", initialToken: "tok" });

    // Watched securities: ticker primary, name subtitle, latest close, YTD change
    expect(await screen.findByText("NVDA")).toBeInTheDocument();
    expect(screen.getByText("NVIDIA Corp")).toBeInTheDocument();
    expect(screen.getByText("$158.11")).toBeInTheDocument();
    expect(screen.getByText("-3.21%")).toBeInTheDocument();
    expect(screen.getByText("DOGE")).toBeInTheDocument();
    expect(screen.getByText("ETH")).toBeInTheDocument();

    // Watched securities list even when they're also held
    expect(screen.getByText("COIN")).toBeInTheDocument();

    // Held-only securities are not listed
    expect(screen.queryByText("AAPL")).not.toBeInTheDocument();
    expect(screen.queryByText("VTI")).not.toBeInTheDocument();
    expect(screen.queryByText("BTC")).not.toBeInTheDocument();

    // Unwatched, unheld securities are not listed
    expect(screen.queryByText("TSLA")).not.toBeInTheDocument();

    // No section headers or instrument-class grouping
    expect(screen.queryByRole("button", { name: "Watchlist" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Holdings" })).not.toBeInTheDocument();
    expect(screen.queryByText("Equities & funds")).not.toBeInTheDocument();

    // With nothing selected the main pane is the market overview dashboard
    expect(await screen.findByText("S&P 500")).toBeInTheDocument();
    expect(screen.getByText("Top Gainers")).toBeInTheDocument();
    expect(screen.getByText("NVIDIA announces the next thing")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/market");
    expect(apiMock.get).toHaveBeenCalledWith("/market/summary");
  });

  it("shows an empty state when there are no securities", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/market") return [] as never;
      return [] as never;
    });

    renderApp({ initialPath: "/market", initialToken: "tok" });
    expect(await screen.findByText("No securities yet")).toBeInTheDocument();
    expect(screen.getByText("Add a ticker to start tracking.")).toBeInTheDocument();
  });

  it("filters the list by search query and shows a no-match message", async () => {
    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("NVDA");

    const search = screen.getByPlaceholderText(/Search securities/);
    fireEvent.change(search, { target: { value: "nvda" } });

    expect(screen.getByText("NVDA")).toBeInTheDocument();
    expect(screen.queryByText("DOGE")).not.toBeInTheDocument();
    expect(screen.queryByText("ETH")).not.toBeInTheDocument();

    fireEvent.change(search, { target: { value: "ZZZZ" } });
    expect(screen.getByText("No securities match the current filters.")).toBeInTheDocument();
  });

  it("doesn't repeat a watched-and-held security under 'Already tracked'", async () => {
    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("COIN");

    fireEvent.change(screen.getByPlaceholderText(/Search securities/), { target: { value: "coin" } });

    // One row, in the watchlist — not a second copy under "Already tracked",
    // which here holds only the unwatched name match (Bitcoin).
    expect(screen.getAllByText("COIN")).toHaveLength(1);
    expect(screen.getByText("Already tracked")).toBeInTheDocument();
    expect(screen.getByText("BTC")).toBeInTheDocument();
  });

  it("surfaces held securities under 'Already tracked' when searched", async () => {
    // Regression: held tickers (excluded from both the watchlist and the
    // remote lookup) were invisible to search — only derivative lookalikes
    // from the provider showed.
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/market") return SECURITIES as never;
      if (path === "/market/AAPL") return { ...NVDA_DETAIL, id: "sec-aapl", ticker: "AAPL", name: "Apple Inc" } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("NVDA");

    fireEvent.change(screen.getByPlaceholderText(/Search securities/), { target: { value: "aapl" } });

    expect(screen.getByText("Already tracked")).toBeInTheDocument();
    expect(screen.getByText("AAPL")).toBeInTheDocument();
    expect(screen.queryByText("NVDA")).not.toBeInTheDocument();

    // Clicking a tracked match opens its detail pane
    fireEvent.click(screen.getByText("AAPL"));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/market/AAPL");
    });
  });

  it("searches without crashing when a watched security has no ticker or name", async () => {
    // Regression: identifier-less securities crashed the page on the first
    // keystroke via s.ticker.includes(q).
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/market") return [
        ...SECURITIES,
        {
          id: "sec-bond", ticker: null, name: null, security_type: "Bond",
          instrument_class: "bond", display_name: "912828XG0",
          latest_price: null, ytd_change_pct: null, day_change_pct: null, spark: [], market_value: 0, watched: true,
        },
      ] as never;
      return [] as never;
    });

    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("NVDA");

    const search = screen.getByPlaceholderText(/Search securities/);
    fireEvent.change(search, { target: { value: "nvda" } });

    expect(screen.getByText("NVDA")).toBeInTheDocument();
    expect(screen.queryByText("DOGE")).not.toBeInTheDocument();
  });
});

describe("Market: staleness", () => {
  it("renders staleness badges with the price source as tooltip", async () => {
    renderApp({ initialPath: "/market", initialToken: "tok" });

    // 6-day-old price → amber badge titled with the provider
    const amber = await screen.findByText("6d stale");
    expect(amber).toHaveAttribute("title", "Last price from CoinMarketCap");
    expect(amber.className).toContain("text-warning");

    // 12-day-old price → red badge
    const red = screen.getByText("12d stale");
    expect(red).toHaveAttribute("title", "Last price from CoinGecko");
    expect(red.className).toContain("text-negative");

    // Ages within the 5-day weekend/holiday allowance carry no badge but
    // keep the source as title.
    expect(screen.queryByText("0d stale")).not.toBeInTheDocument();
    expect(screen.queryByText("3d stale")).not.toBeInTheDocument();
    expect(screen.getByText("$158.11")).toHaveAttribute("title", "Alpha Vantage");
  });
});

describe("Market: watch / unwatch", () => {
  it("POSTs /market/watch with the typed ticker", async () => {
    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("NVDA");

    fireEvent.click(screen.getByTitle("Add to watchlist"));
    const input = screen.getByPlaceholderText(/Ticker symbol/);
    fireEvent.change(input, { target: { value: "msft" } });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/market/watch", { ticker: "MSFT", name: undefined });
    });

    // Post-watch sync indicator
    expect(await screen.findByText(/Fetching prices for MSFT/)).toBeInTheDocument();
  });

  it("POSTs /market/watch with ticker and name when a suggestion is clicked", async () => {
    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("NVDA");

    fireEvent.click(screen.getByTitle("Add to watchlist"));
    fireEvent.change(screen.getByPlaceholderText(/Ticker symbol/), { target: { value: "TS" } });

    // TSLA is known but unwatched/unheld, so it shows up as a suggestion
    fireEvent.click(await screen.findByText("TSLA"));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/market/watch", { ticker: "TSLA", name: "Tesla Inc" });
    });
  });

  it("DELETEs /market/:ticker/unwatch when removing a watchlist row", async () => {
    renderApp({ initialPath: "/market", initialToken: "tok" });

    const row = (await screen.findByText("NVDA")).closest("button");
    expect(row).not.toBeNull();

    // The remove affordance is a nested role="button" inside the row
    fireEvent.click(within(row!).getByRole("button"));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/market/NVDA/unwatch");
    });
  });
});

describe("Market: remote ticker search", () => {
  const REMOTE_RESULTS = {
    results: [
      { ticker: "PLTR", name: "Palantir Technologies Inc", security_type: "Equity",
        region: "United States", currency: "USD", instrument_class: "equity", match_score: 1.0 },
    ],
  };

  function stubRemoteSearch() {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/market") return SECURITIES as never;
      if (path.startsWith("/market/search?q=PLTR")) return REMOTE_RESULTS as never;
      if (path === "/market/PLTR") return { ...NVDA_DETAIL, id: "sec-pltr", ticker: "PLTR", name: "Palantir Technologies Inc" } as never;
      return [] as never;
    });
  }

  it("shows provider matches under 'Not in your list' for unknown tickers", async () => {
    stubRemoteSearch();
    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("NVDA");

    fireEvent.change(screen.getByPlaceholderText("Search securities…"), { target: { value: "PLTR" } });

    expect(await screen.findByText("Not in your list")).toBeInTheDocument();
    expect(await screen.findByText("PLTR")).toBeInTheDocument();
    expect(screen.getByText("Palantir Technologies Inc")).toBeInTheDocument();
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/market/search?q=PLTR", { signal: expect.any(AbortSignal) });
    });
  });

  it("tracks a remote result on click and opens its detail pane", async () => {
    stubRemoteSearch();
    apiMock.post.mockResolvedValue({ id: "sec-pltr", ticker: "PLTR", watched: true, syncing: true } as never);
    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("NVDA");

    fireEvent.change(screen.getByPlaceholderText("Search securities…"), { target: { value: "PLTR" } });
    fireEvent.click(await screen.findByRole("button", { name: /PLTR.*Palantir/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/market/watch", {
        ticker: "PLTR", name: "Palantir Technologies Inc", instrument_class: "equity",
      });
    });
    // Detail pane opens on the new ticker
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/market/PLTR");
    });
  });

  it("does not query the provider for short inputs", async () => {
    stubRemoteSearch();
    renderApp({ initialPath: "/market", initialToken: "tok" });
    await screen.findByText("NVDA");

    fireEvent.change(screen.getByPlaceholderText("Search securities…"), { target: { value: "P" } });

    await new Promise((r) => setTimeout(r, 400));
    expect(apiMock.get).not.toHaveBeenCalledWith(expect.stringContaining("/market/search"));
  });
});

describe("Market: detail pane", () => {
  it("clicking a security loads its detail pane", async () => {
    renderApp({ initialPath: "/market", initialToken: "tok" });

    fireEvent.click(await screen.findByText("NVDA"));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/market/NVDA");
    });

    // Detail-pane chrome replaces the placeholder. "Add transaction" now lives
    // in the "Page actions" pencil dropdown of the detail pane's header
    // (menu items render in a portal on document.body).
    await userEvent.setup().click(await screen.findByRole("button", { name: /Page actions/i }));
    expect(await screen.findByRole("menuitem", { name: /Add transaction/i })).toBeInTheDocument();
    expect(screen.getByText("View On")).toBeInTheDocument();
    // The overview dashboard is replaced by the detail pane
    expect(screen.queryByText("Top Gainers")).not.toBeInTheDocument();
  });

  it("watches the security from the link beside the price timestamp", async () => {
    // Standalone detail route: the list's icon-only "+" toggle carries the
    // same label, and this test is about the detail link.
    renderApp({ initialPath: "/market/NVDA", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: "Add to watchlist" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/market/watch", {
        ticker: "NVDA", name: "NVIDIA Corp", instrument_class: "equity",
      });
    });
  });

  it("offers removal instead when the security is already watched", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/market") return SECURITIES as never;
      if (path === "/market/NVDA") return { ...NVDA_DETAIL, watched: true } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/market/NVDA", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: "Remove from watchlist" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/market/NVDA/unwatch");
    });
  });

  it("hides the watchlist link for crypto, which isn't watchable", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/market") return SECURITIES as never;
      if (path === "/market/BTC") {
        return { ...NVDA_DETAIL, id: "sec-btc", ticker: "BTC", name: "Bitcoin",
                 security_type: "Crypto", instrument_class: "crypto" } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/market/BTC", initialToken: "tok" });

    await screen.findByText(/As of/);
    expect(screen.queryByRole("button", { name: "Add to watchlist" })).not.toBeInTheDocument();
  });
});
