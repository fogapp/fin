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
import type { StatsIndexData, StatDetailData } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

// Fixture matrix: currency/flow/partial + drill + breakdowns, count/flow,
// percent/flow, currency/level — exercises every unit/value_type pairing.
const STATS_INDEX: StatsIndexData = {
  as_of: "2026-07-11T06:45:00Z",
  groups: [
    { key: "cashflow", label: "Cashflow" },
    { key: "net_worth", label: "Net Worth" },
  ],
  stats: [
    {
      key: "monthly_spend", label: "Monthly spend", description: "Total spending each month.",
      group: "cashflow", unit: "currency", granularity: "month", value_type: "flow", direction: "down_good",
      latest: { date: "2026-07", value: 4321.1, partial: true },
      previous: { date: "2026-06", value: 4000, partial: false },
      change_pct: 12.0,
      pace: { projected: 12963.3, vs_previous_pct: 12.0 },
      sparkline: [
        { date: "2026-05", value: 3800 },
        { date: "2026-06", value: 4000 },
        { date: "2026-07", value: 4321.1, partial: true },
      ],
      drill: { route: "/transactions", params: {} },
    },
    {
      key: "cc_transaction_count", label: "Credit-card transactions", description: null,
      group: "cashflow", unit: "count", granularity: "month", value_type: "flow", direction: "neutral",
      latest: { date: "2026-07", value: 1234, partial: true },
      previous: { date: "2026-06", value: 1200, partial: false },
      change_pct: 2.8,
      pace: { projected: 3702, vs_previous_pct: 2.8 },
      sparkline: [
        { date: "2026-06", value: 1200 },
        { date: "2026-07", value: 1234, partial: true },
      ],
      drill: { route: "/transactions", params: { source: "credit_card" } },
    },
    {
      key: "savings_rate", label: "Savings rate", description: null,
      group: "cashflow", unit: "percent", granularity: "month", value_type: "flow", direction: "up_good",
      latest: { date: "2026-06", value: 23.42, partial: false },
      previous: { date: "2026-05", value: 20, partial: false },
      change_pct: 17.1,
      pace: null,
      sparkline: [
        { date: "2026-05", value: 20 },
        { date: "2026-06", value: 23.42 },
      ],
      drill: null,
    },
    {
      key: "net_worth", label: "Net worth", description: null,
      group: "net_worth", unit: "currency", granularity: "day", value_type: "level", direction: "up_good",
      latest: { date: "2026-07-11", value: 1200000, partial: true },
      previous: { date: "2026-06-11", value: 1100000, partial: false },
      change_pct: 9.1,
      pace: null,
      sparkline: [
        { date: "2026-07-09", value: 1150000 },
        { date: "2026-07-10", value: 1180000 },
        { date: "2026-07-11", value: 1200000, partial: true },
      ],
      drill: null,
    },
  ],
};

const SPEND_DETAIL: StatDetailData = {
  key: "monthly_spend", label: "Monthly spend", description: "Total spending each month.",
  group: "cashflow", unit: "currency", granularity: "month", value_type: "flow", direction: "down_good",
  range: { from: "2025-07-01", to: "2026-07-11" },
  series: [
    { date: "2026-05", value: 3800, partial: false },
    { date: "2026-06", value: 4000, partial: false },
    { date: "2026-07", value: 4321.1, partial: true },
  ],
  summary: {
    latest: { date: "2026-07", value: 4321.1, partial: true },
    previous: { date: "2026-06", value: 4000, partial: false },
    change_pct: 12.0,
    pace: { projected: 12963.3, vs_previous_pct: 12.0 },
    min: { date: "2026-05", value: 3800 },
    max: { date: "2026-06", value: 4000 },
    avg: 3900,
    changes: { "1m": 5.3, "3m": 8.1, ytd: 12.2, "1y": -2.0 },
  },
  breakdowns: [
    { label: "Top categories", rows: [
      { label: "Groceries", value: 1200.5 },
      { label: "Dining", value: 800 },
    ] },
  ],
  drill: { route: "/transactions", params: {} },
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
    if (path === "/stats") return STATS_INDEX as never;
    if (path.startsWith("/stats/monthly_spend")) return SPEND_DETAIL as never;
    return [] as never;
  });
});

describe("Stats: index", () => {
  it("groups cards by domain with per-unit formatting and polarity", async () => {
    renderApp({ initialPath: "/stats", initialToken: "tok" });

    // Domain headings from groups[] (sidebar nav links also match the text)
    await screen.findByText("Monthly spend");
    expect(screen.getAllByText("Cashflow").filter((el) => el.closest("nav") === null)).toHaveLength(1);
    expect(screen.getAllByText("Net Worth").filter((el) => el.closest("nav") === null)).toHaveLength(1);

    // Unit formatting: currency full-precision, count grouped, percent unsigned
    expect(screen.getByText("$4,321.10")).toBeInTheDocument();
    expect(screen.getByText("1,234")).toBeInTheDocument();
    expect(screen.getByText("23.4%")).toBeInTheDocument();

    // Polarity: spend up 12% with down_good → negative color
    expect(screen.getByText("+12.0%")).toHaveClass("tabular-nums");
    expect(screen.getByText("+12.0%").closest("span.inline-flex")).toHaveClass("text-negative");
    // Net worth up with up_good → positive color
    expect(screen.getByText("+9.1%").closest("span.inline-flex")).toHaveClass("text-positive");

    // MTD tag only on partial flow cards
    expect(screen.getAllByText("MTD")).toHaveLength(2); // spend + cc count

    // Whole card links to the detail page
    const card = screen.getByText("Monthly spend").closest("a");
    expect(card).toHaveAttribute("href", "/stats/monthly_spend");
  });

  it("shows an error state with retry when the index fails", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/stats") throw new Error("boom");
      return [] as never;
    });

    renderApp({ initialPath: "/stats", initialToken: "tok" });
    expect(await screen.findByText("Failed to load stats")).toBeInTheDocument();
  });
});

describe("Stats: detail", () => {
  it("renders hero, summary ribbon, breakdowns, and drill-through", async () => {
    renderApp({ initialPath: "/stats/monthly_spend", initialToken: "tok" });

    // Hero value + pace annotation for the in-progress month
    expect(await screen.findByText("Total spending each month.")).toBeInTheDocument();
    expect(screen.getAllByText("$4,321.10").length).toBeGreaterThan(0);
    expect(screen.getByText(/Month in progress/)).toBeInTheDocument();
    expect(screen.getByText(/Projected \$12,963\.30 at this pace/)).toBeInTheDocument();

    // Summary ribbon: labeled MTD, prior month (also the max), average
    expect(screen.getByText("This month (MTD)")).toBeInTheDocument();
    expect(screen.getAllByText("$4,000.00").length).toBeGreaterThan(0);
    expect(screen.getByText("$3,900.00")).toBeInTheDocument();

    // Breakdown rail
    expect(screen.getByText("Top categories")).toBeInTheDocument();
    expect(screen.getByText("Groceries")).toBeInTheDocument();
    expect(screen.getByText("$1,200.50")).toBeInTheDocument();

    // Drill-through action lives in the page-actions dropdown in the header
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    expect(await screen.findByRole("menuitem", { name: /View transactions/i })).toBeInTheDocument();
  });

  it("refetches when the timeframe changes and persists the preset", async () => {
    renderApp({ initialPath: "/stats/monthly_spend", initialToken: "tok" });
    await screen.findByText("This month (MTD)");

    fireEvent.click(screen.getByRole("button", { name: "3M" }));

    await waitFor(() => {
      const calls = apiMock.get.mock.calls.map(([p]) => p).filter((p: string) => p.startsWith("/stats/monthly_spend"));
      expect(calls.length).toBeGreaterThan(1);
    });
    expect(sessionStorage.getItem("stats-timeframe")).toBe("3m");
  });

  it("shows an error state for an unknown stat", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/stats/")) throw new Error("Unknown stat");
      return [] as never;
    });

    renderApp({ initialPath: "/stats/not_a_stat", initialToken: "tok" });
    expect(await screen.findByText("Failed to load stat")).toBeInTheDocument();
    expect(screen.getByText("Unknown stat")).toBeInTheDocument();
  });
});
