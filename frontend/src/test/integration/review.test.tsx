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
import type { ReviewData } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const REVIEW: ReviewData = {
  month: "2026-06",
  cashflow: {
    income: 9000, spend: 5400, net: 3600,
    prev_income: 8000, prev_spend: 6000, prev_net: 2000,
    savings_rate: 40.0,
  },
  top_categories: [
    { id: "c1", name: "Groceries", amount: 1200 },
    { id: "c2", name: "Dining", amount: 640 },
  ],
  top_merchants: [{ id: "m1", name: "Costco", amount: 800 }],
  largest_transactions: [{
    id: "tx-9", description: "Delta Airlines", category_name: "Travel",
    transaction_date: "2026-06-14", amount: 1450,
  }],
  net_worth: { ending: 512_000, starting: 505_000, change: 7_000 },
  budget: { planned: 6000, actual: 5400, remaining: 600 },
  subscriptions: { paid_count: 9, paid_total: 214.55 },
};

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  vi.stubGlobal("fetch", vi.fn());
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path.startsWith("/review")) return REVIEW as never;
    return [] as never;
  });
});

describe("Monthly review page", () => {
  it("renders the month's summary, rankings, and cards", async () => {
    renderApp({ initialPath: "/review?month=2026-06", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Review · June 2026" })).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/review?month=2026-06");

    // Ribbon: income/spend/net/savings rate + net worth
    expect(await screen.findByText("$9K")).toBeInTheDocument();
    expect(screen.getByText("$5.4K")).toBeInTheDocument();
    expect(screen.getByText("40.0%")).toBeInTheDocument();
    // Net worth shows in the ribbon and in its own card.
    expect(screen.getAllByText("$512K")).toHaveLength(2);

    // Rankings + largest transactions
    expect(screen.getByText("Groceries")).toBeInTheDocument();
    expect(screen.getByText("Costco")).toBeInTheDocument();
    expect(screen.getByText("Delta Airlines")).toBeInTheDocument();

    // Budget outcome favors the leftover framing when under budget
    expect(screen.getByText("Left over")).toBeInTheDocument();
  });

  it("navigates to the previous month", async () => {
    renderApp({ initialPath: "/review?month=2026-06", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Review · June 2026" });

    fireEvent.click(screen.getByRole("button", { name: "Previous month" }));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/review?month=2026-05");
    });
  });
});
