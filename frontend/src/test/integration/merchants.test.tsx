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
import type { MerchantSummary, MerchantDetail } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const MERCHANTS: MerchantSummary[] = [
  { id: "m1", name: "Starbucks", category_id: "c1", category_name: "Coffee", notes: "Morning runs", transaction_count: 120, excluded: false },
  { id: "m2", name: "Walmart", category_id: null, category_name: null, notes: null, transaction_count: 45, excluded: false },
];

const STARBUCKS_DETAIL: MerchantDetail = {
  id: "m1",
  name: "Starbucks",
  category_id: "c1",
  category_name: "Coffee",
  notes: "Morning runs",
  excluded: false,
  transaction_count: 120,
  monthly_spend: { "2026-06": 80.25, "2026-05": 60 },
  monthly_counts: { "2026-06": 12, "2026-05": 9 },
  monthly_income: {},
};

const WALMART_DETAIL: MerchantDetail = {
  id: "m2",
  name: "Walmart",
  category_id: null,
  category_name: null,
  notes: null,
  excluded: false,
  transaction_count: 45,
  monthly_spend: { "2026-06": 200 },
  monthly_counts: { "2026-06": 4 },
  monthly_income: {},
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
    if (path === "/merchants") return MERCHANTS as never;
    if (path === "/merchants/m1") return STARBUCKS_DETAIL as never;
    if (path === "/merchants/m2") return WALMART_DETAIL as never;
    // The Monthly Spend chart is a SpendChartCard compact, fed by the
    // merchant-scoped breakdown endpoint.
    if (path.startsWith("/cashflow/spend_breakdown")) {
      return { monthly_spend: { "2026-06": 80.25, "2026-05": 60 } } as never;
    }
    if (path.startsWith("/cash_transactions")) return [] as never;
    return [] as never;
  });
});

describe("Merchants: list", () => {
  it("renders merchants with transaction counts and an empty detail prompt", async () => {
    renderApp({ initialPath: "/merchants", initialToken: "tok" });

    expect(await screen.findByText("Starbucks")).toBeInTheDocument();
    expect(screen.getByText("Walmart")).toBeInTheDocument();
    expect(screen.getByText("120")).toBeInTheDocument();
    expect(screen.getByText("45")).toBeInTheDocument();

    expect(screen.getByText("Select a merchant to see details")).toBeInTheDocument();
  });

  it("filters merchants via search and shows an empty state when nothing matches", async () => {
    renderApp({ initialPath: "/merchants", initialToken: "tok" });
    await screen.findByText("Starbucks");

    const input = screen.getByPlaceholderText(/Search merchants/);
    fireEvent.change(input, { target: { value: "wal" } });

    expect(screen.getByText("Walmart")).toBeInTheDocument();
    expect(screen.queryByText("Starbucks")).not.toBeInTheDocument();

    fireEvent.change(input, { target: { value: "zzz" } });
    expect(screen.getByText("No merchants match the current filters.")).toBeInTheDocument();
  });
});

describe("Merchants: detail", () => {
  it("clicking a merchant shows its detail panel with category link, notes and stats", async () => {
    renderApp({ initialPath: "/merchants", initialToken: "tok" });

    fireEvent.click(await screen.findByText("Starbucks"));

    expect(await screen.findByRole("heading", { name: "Starbucks" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Coffee" })).toBeInTheDocument();
    // Notes render prefixed with "·" when a category is also set
    expect(screen.getByText(/Morning runs/)).toBeInTheDocument();
    // Total spend stat = sum of monthly_spend within the charted window
    expect(screen.getByText("$140.25")).toBeInTheDocument();

    expect(apiMock.get).toHaveBeenCalledWith("/merchants/m1");
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?merchant_id=m1");

    // The Monthly Spend chart is the canonical spend card scoped to this merchant
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(expect.stringMatching(/\/cashflow\/spend_breakdown\?.*merchant_id=m1/));
    });
  });

  it("hides the category link for an uncategorized merchant", async () => {
    renderApp({ initialPath: "/merchants#id=m2", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Walmart" })).toBeInTheDocument();
    // No category link when the merchant is uncategorized
    expect(screen.queryByRole("link", { name: "Coffee" })).not.toBeInTheDocument();
  });

  it("shows an error message when the detail request fails", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/merchants") return MERCHANTS as never;
      if (path === "/merchants/m1") throw new Error("HTTP 500");
      return [] as never;
    });

    renderApp({ initialPath: "/merchants#id=m1", initialToken: "tok" });
    expect(await screen.findByText("Failed to load merchant")).toBeInTheDocument();
  });
});

describe("Merchants: create", () => {
  it("creates a merchant via the inline form and selects it", async () => {
    apiMock.post.mockResolvedValue({
      id: "m9", name: "Costco", category_id: null, category_name: null,
      notes: null, transaction_count: 0, excluded: false,
    } as never);
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/merchants") return MERCHANTS as never;
      if (path === "/merchants/m9") return {
        ...WALMART_DETAIL, id: "m9", name: "Costco", transaction_count: 0,
        monthly_spend: {}, monthly_counts: {}, monthly_income: {},
      } as never;
      if (path.startsWith("/cash_transactions")) return [] as never;
      return [] as never;
    });

    renderApp({ initialPath: "/merchants", initialToken: "tok" });
    await screen.findByText("Starbucks");

    fireEvent.click(screen.getByTitle("New merchant"));
    fireEvent.change(screen.getByPlaceholderText("Merchant name"), { target: { value: "Costco" } });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/merchants", { name: "Costco" });
    });
    expect(await screen.findByRole("heading", { name: "Costco" })).toBeInTheDocument();
  });

  it("shows a validation error when submitting a blank name", async () => {
    renderApp({ initialPath: "/merchants", initialToken: "tok" });
    await screen.findByText("Starbucks");

    fireEvent.click(screen.getByTitle("New merchant"));
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    expect(await screen.findByText("Name is required")).toBeInTheDocument();
    expect(apiMock.post).not.toHaveBeenCalled();
  });
});
