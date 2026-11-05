import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, fireEvent, within } from "@testing-library/react";

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
import { isoDate, timeframeRange } from "@/components/charts";
import type { NetWorthData } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const NET_WORTH: NetWorthData = {
  range: "1y",
  from: "2025-06-15",
  to: isoDate(),
  series: [
    { date: "2026-06-01", cash: 40000, investments: 100000, crypto: 0, real_estate: 0, equity: 0, credit: -4000, loans: -32000, assets: 140000, liabilities: 36000, net: 104000 },
    { date: "2026-06-15", cash: 45000, investments: 102000, crypto: 0, real_estate: 0, equity: 0, credit: -5000, loans: -31500, assets: 147000, liabilities: 36500, net: 110500 },
    { date: "2026-07-02", cash: 45000, investments: 105000, crypto: 0, real_estate: 0, equity: 0, credit: -9000, loans: -31000, assets: 150000, liabilities: 40000, net: 110000 },
  ],
  stats: {
    net_worth: 110000, assets: 150000, liabilities: 40000,
    cash: 45000, investments: 105000, crypto: 0, real_estate: 0, equity: 0, credit: 9000, loans: 31000,
    changes: {
      "1m": { amount: 6000, pct: 5.77 },
      "3m": { amount: 9000, pct: 8.91 },
      ytd: { amount: 15000, pct: 15.79 },
      "1y": { amount: 30000, pct: 37.5 },
    },
  },
  monthly_deltas: [
    { month: "2026-05", change: 2000 },
    { month: "2026-06", change: 6500 },
    { month: "2026-07", change: -500 },
  ],
  accounts: [
    { id: "a1", name: "Brokerage", broker: "Schwab", account_type: "Brokerage", group: "investments", value: 105000, start_value: 80000, change: 25000, change_pct: 31.25 },
    { id: "a2", name: "Everyday Checking", broker: "Chase", account_type: "Checking", group: "cash", value: 45000, start_value: 40000, change: 5000, change_pct: 12.5 },
    { id: "a3", name: "Sapphire Card", broker: "Chase", account_type: "Credit Card", group: "credit", value: 9000, start_value: 4000, change: 5000, change_pct: 125.0 },
  ],
  loans: [
    { id: "l1", name: "Mortgage", loan_type: "mortgage", lender: "Rocket", value: 31000, start_value: 34000, change: -3000, change_pct: -8.82 },
  ],
  properties: [],
  equity: [],
};

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path.startsWith("/net_worth")) return NET_WORTH as never;
    return [] as never;
  });
});

describe("Net worth page", () => {
  it("renders stats and a grouped balance sheet", async () => {
    renderApp({ initialPath: "/net-worth", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Net Worth" })).toBeInTheDocument();

    // Stat ribbon
    expect(screen.getByText("$110K")).toBeInTheDocument();   // net worth
    expect(screen.getByText("$150K")).toBeInTheDocument();   // assets
    expect(screen.getByText("$40K")).toBeInTheDocument();    // liabilities

    // Scoped to the sheet — the sidebar repeats labels like "Investments"
    const sheet = within(await screen.findByRole("table"));

    // Asset groups, each naming the single account it holds
    expect(sheet.getByText("Investments")).toBeInTheDocument();
    expect(sheet.getByText(/Brokerage/)).toBeInTheDocument();
    expect(sheet.getByText(/Everyday Checking/)).toBeInTheDocument();
    expect(sheet.getByText("$105,000.00")).toBeInTheDocument();

    // Liability groups: credit card account and replayed loan stay separate
    expect(sheet.getByText("Credit Cards")).toBeInTheDocument();
    expect(sheet.getByText(/Sapphire Card/)).toBeInTheDocument();
    expect(sheet.getByText("Loans")).toBeInTheDocument();
    expect(sheet.getByText("$31,000.00")).toBeInTheDocument();

    // Balance-sheet totals, read off their own rows ($40,000.00 also appears
    // as cash's start-of-range value)
    const rowFor = (label: string) => within(sheet.getByText(label).closest("tr") as HTMLElement);
    expect(rowFor("Total assets").getByText("$150,000.00")).toBeInTheDocument();
    expect(rowFor("Total liabilities").getByText("$40,000.00")).toBeInTheDocument();
    expect(rowFor("Net worth").getByText("$110,000.00")).toBeInTheDocument();

    const { from, to } = timeframeRange("1y");
    expect(apiMock.get).toHaveBeenCalledWith(`/net_worth?from=${from}&to=${to}`);
  });

  it("shows the change over the selected range beside each line", async () => {
    renderApp({ initialPath: "/net-worth", initialToken: "tok" });
    const sheet = within(await screen.findByRole("table"));

    // Brokerage: 80,000 → 105,000 over the 1y window
    expect(sheet.getByText("+$25,000.00")).toBeInTheDocument();
    expect(sheet.getByText("+31.3%")).toBeInTheDocument();
    // The start column is labelled with the window's start date; a window
    // ending today leaves the end column as plain "Value".
    expect(sheet.getByText("Jun 15, 2025")).toBeInTheDocument();
    expect(sheet.getByText("Value")).toBeInTheDocument();
  });

  it("names the end column when the window stops short of today", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/net_worth")) return { ...NET_WORTH, from: "2025-01-01", to: "2025-12-31" } as never;
      return [] as never;
    });
    renderApp({ initialPath: "/net-worth", initialToken: "tok" });
    const sheet = within(await screen.findByRole("table"));

    expect(sheet.getByText("Jan 1, 2025")).toBeInTheDocument();
    expect(sheet.getByText("Dec 31, 2025")).toBeInTheDocument();
  });

  it("asks for everything on record under All", async () => {
    renderApp({ initialPath: "/net-worth", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Net Worth" });

    fireEvent.click(screen.getByRole("button", { name: "All" }));
    await waitFor(() => expect(apiMock.get).toHaveBeenCalledWith("/net_worth?range=all"));
  });

  it("lists property value as an asset while its mortgage stays a liability", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/net_worth")) {
        return {
          ...NET_WORTH,
          stats: { ...NET_WORTH.stats, real_estate: 912000 },
          properties: [
            {
              id: "p1", name: "Primary residence", address: "5500 Grand Lake Dr",
              status: "owned" as const, value: 912000, start_value: 880000,
              change: 32000, change_pct: 3.64, mortgage_balance: 418300, equity: 493700,
            },
          ],
        } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/net-worth", initialToken: "tok" });

    // Gross value under Assets, with the equity/mortgage split as context…
    const sheet = within(await screen.findByRole("table"));
    expect(sheet.getByText("Real Estate")).toBeInTheDocument();
    expect(sheet.getByText(/Primary residence/)).toBeInTheDocument();
    expect(sheet.getByText(/\$493\.7K equity/)).toBeInTheDocument();
    expect(sheet.getByText("$912,000.00")).toBeInTheDocument();
    // …and the mortgage still counted once, under Liabilities.
    expect(sheet.getByText(/Mortgage/)).toBeInTheDocument();
    expect(sheet.getByText("$31,000.00")).toBeInTheDocument();
  });

  it("lists equity companies as assets with their vesting scope", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/net_worth")) {
        return {
          ...NET_WORTH,
          equity: [
            {
              id: "e1", name: "Acme", ticker: null, public_company: false, grant_count: 2,
              value: 84000, start_value: 60000, change: 24000, change_pct: 40,
              vested_value: 84000, unvested_value: 126000, include_unvested: false,
            },
          ],
        } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/net-worth", initialToken: "tok" });

    const sheet = within(await screen.findByRole("table"));
    expect(sheet.getByText("Equity")).toBeInTheDocument();
    expect(sheet.getByText(/Acme/)).toBeInTheDocument();
    expect(sheet.getByText("$84,000.00")).toBeInTheDocument();
    expect(sheet.getByText(/unvested excluded/)).toBeInTheDocument();
  });

  it("collapses large groups and expands them on click", async () => {
    const wallets = Array.from({ length: 8 }, (_, i) => ({
      id: `w${i}`, name: `Wallet ${i}`, broker: "Coinbase", account_type: "crypto",
      group: "crypto" as const, value: 1000 - i, start_value: 900 - i, change: 100, change_pct: 11.1,
    }));
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/net_worth")) {
        return { ...NET_WORTH, accounts: [...NET_WORTH.accounts, ...wallets] } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/net-worth", initialToken: "tok" });
    const sheet = within(await screen.findByRole("table"));

    // 8 wallets is past the auto-collapse threshold: the subtotal shows, the
    // members don't, until the group is opened.
    const toggle = sheet.getByRole("button", { name: /Crypto/ });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(sheet.queryByText("Wallet 0")).not.toBeInTheDocument();

    fireEvent.click(toggle);
    expect(sheet.getByText("Wallet 0")).toBeInTheDocument();
    expect(toggle).toHaveAttribute("aria-expanded", "true");
  });

  it("withholds a percent when a line has no history at the range start", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/net_worth")) {
        return {
          ...NET_WORTH,
          accounts: [{
            id: "a9", name: "Brand New Savings", broker: "Ally", account_type: "Savings",
            group: "cash" as const, value: 12000, start_value: null, change: 12000, change_pct: null,
          }],
          loans: [], properties: [], equity: [],
        } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/net-worth", initialToken: "tok" });
    const sheet = within(await screen.findByRole("table"));

    // Dollars still count (line, group subtotal, totals); the percent would be
    // growth-from-nothing fiction.
    expect(sheet.getAllByText("+$12,000.00").length).toBeGreaterThan(0);
    expect(sheet.getAllByText("—").length).toBeGreaterThan(0);
    // Signed percentages are the change column's; the unsigned "100.0%" in the
    // share column is unrelated.
    expect(sheet.queryByText(/^[+-][\d.]+%$/)).not.toBeInTheDocument();
  });

  it("survives a cached payload from before the equity bucket existed", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/net_worth")) {
        // Exactly what a pre-deploy cache entry / revalidated ETag returns.
        const legacy = Object.fromEntries(
          Object.entries(NET_WORTH).filter(([k]) => k !== "equity" && k !== "properties"),
        );
        return legacy as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/net-worth", initialToken: "tok" });

    const sheet = within(await screen.findByRole("table"));
    expect(sheet.getByText("Net worth")).toBeInTheDocument();
    expect(sheet.getByText(/Everyday Checking/)).toBeInTheDocument();
  });

  it("switches ranges and refetches", async () => {
    renderApp({ initialPath: "/net-worth", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Net Worth" });

    fireEvent.click(screen.getByRole("button", { name: "3M" }));
    const { from, to } = timeframeRange("3m");
    await waitFor(() => expect(apiMock.get).toHaveBeenCalledWith(`/net_worth?from=${from}&to=${to}`));
    expect(sessionStorage.getItem("net-worth-timeframe")).toBe("3m");
  });

  it("shows an empty state when there is no balance history", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/net_worth")) {
        return { ...NET_WORTH, accounts: [], loans: [], properties: [], equity: [] } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/net-worth", initialToken: "tok" });
    expect(await screen.findByText("No balance history yet")).toBeInTheDocument();
  });
});
