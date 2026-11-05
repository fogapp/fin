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
import type { CategorySummary, CategoryDetail, SpendBreakdownData } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const CATEGORIES: CategorySummary[] = [
  { id: "c1", name: "Food", parent_id: null, transaction_count: 42, budget_kind: "flex" },
  { id: "c2", name: "Coffee", parent_id: "c1", transaction_count: 12, budget_kind: "flex" },
  { id: "c3", name: "Travel", parent_id: null, transaction_count: 7, budget_kind: "flex" },
];

const FOOD_DETAIL: CategoryDetail = {
  id: "c1",
  name: "Food",
  parent_id: null,
  parent: null,
  subcategories: [{ id: "c2", name: "Coffee", transaction_count: 12, total_spend: 340.5 }],
  total_count: 42,
  total_spend: 1234.56,
  total_returns: 25,
  by_merchant: { Starbucks: 220.4, "Whole Foods": 890.1 },
  monthly_spend: { "2026-06": 400, "2026-05": 300 },
  monthly_spend_rollup: { "2026-06": 520, "2026-05": 410 },

};

/** The detail page's spend chart feeds itself from the category-scoped
 *  breakdown — for a parent, the "category" bands are its subcategories. */
const SPEND_BREAKDOWN: SpendBreakdownData = {
  from: "2026-05-01",
  to: "2026-06-30",
  monthly_spend: { "2026-05-01": 410, "2026-06-01": 520 },
  monthly_spend_common: { "2026-05-01": 410, "2026-06-01": 520 },
  category: {
    series: [{ id: "c1", name: "Food" }, { id: "c2", name: "Coffee" }],
    months: {
      "2026-05-01": { c1: 300, c2: 110 },
      "2026-06-01": { c1: 400, c2: 120 },
    },
  },
  category_common: {
    series: [{ id: "c1", name: "Food" }, { id: "c2", name: "Coffee" }],
    months: {
      "2026-05-01": { c1: 300, c2: 110 },
      "2026-06-01": { c1: 400, c2: 120 },
    },
  },
  merchant: { series: [], months: {} },
  merchant_common: { series: [], months: {} },
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
    if (path === "/categories") return CATEGORIES as never;
    if (path === "/categories/c1") return FOOD_DETAIL as never;
    if (path.startsWith("/cashflow/spend_breakdown")) return SPEND_BREAKDOWN as never;
    if (path.startsWith("/cash_transactions")) return [] as never;
    return [] as never;
  });
});

describe("Categories: list", () => {
  it("renders the category tree with transaction counts and an empty detail prompt", async () => {
    renderApp({ initialPath: "/categories", initialToken: "tok" });

    expect(await screen.findByText("Food")).toBeInTheDocument();
    expect(screen.getByText("Coffee")).toBeInTheDocument();  // subcategory nested under Food
    expect(screen.getByText("Travel")).toBeInTheDocument();
    expect(screen.getByText("42")).toBeInTheDocument();
    expect(screen.getByText("12")).toBeInTheDocument();

    expect(screen.getByText("Select a category to see details")).toBeInTheDocument();
  });

  it("filters the list via search and shows an empty state when nothing matches", async () => {
    renderApp({ initialPath: "/categories", initialToken: "tok" });
    await screen.findByText("Food");

    const input = screen.getByPlaceholderText(/Search categories/);
    fireEvent.change(input, { target: { value: "cof" } });

    expect(screen.getByText("Coffee")).toBeInTheDocument();
    expect(screen.queryByText("Travel")).not.toBeInTheDocument();
    expect(screen.queryByText("Food")).not.toBeInTheDocument();

    fireEvent.change(input, { target: { value: "zzz" } });
    expect(screen.getByText("No categories match the current filters.")).toBeInTheDocument();
  });
});

describe("Categories: detail", () => {
  it("clicking a category shows its detail panel with stats, subcategories and merchants", async () => {
    renderApp({ initialPath: "/categories", initialToken: "tok" });

    fireEvent.click(await screen.findByText("Food"));

    expect(await screen.findByRole("heading", { name: "Food" })).toBeInTheDocument();
    expect(screen.getByText("$1,234.56")).toBeInTheDocument(); // total spend
    expect(screen.getByText("$25.00")).toBeInTheDocument();    // returns
    // Subcategory row
    expect(screen.getByText("12 txns")).toBeInTheDocument();
    expect(screen.getByText("$340.50")).toBeInTheDocument();
    // Top merchants
    expect(screen.getByText("Whole Foods")).toBeInTheDocument();
    expect(screen.getByText("Starbucks")).toBeInTheDocument();

    expect(apiMock.get).toHaveBeenCalledWith("/categories/c1");
    // Parent detail fetches transactions for itself plus its subcategories
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?category_ids=c1,c2");
  });

  it("feeds the spend chart from the category-scoped breakdown, defaulting parents to the subcategory split", async () => {
    renderApp({ initialPath: "/categories#id=c1", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Food" });

    // Self-sufficient chart: one endpoint, scoped to the category rollup.
    const { from, to } = timeframeRange("1y");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/spend_breakdown?from=${from}&to=${to}&category_id=c1`);
    });

    // A parent with subcategories opens on the by-category split…
    expect(await screen.findByText(/Each month's spend by category · top 8/)).toBeInTheDocument();
    // …with the chart's own controls, since this page has no scoping header.
    expect(screen.getByRole("group", { name: "Spend series" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Timeframe" })).toBeInTheDocument();

    // Switching to Total drops the split subtitle.
    await userEvent.click(within(screen.getByRole("group", { name: "Spend split" })).getByText("Total"));
    expect(screen.queryByText(/everything else in Other/)).not.toBeInTheDocument();
  });

  it("shows an error message when the detail request fails", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/categories") return CATEGORIES as never;
      if (path === "/categories/c1") throw new Error("HTTP 500");
      return [] as never;
    });

    renderApp({ initialPath: "/categories#id=c1", initialToken: "tok" });
    expect(await screen.findByText("Failed to load category")).toBeInTheDocument();
  });
});

describe("Categories: create / edit / delete", () => {
  it("creates a new top-level category via the inline form", async () => {
    const created: CategorySummary = { id: "c9", name: "Utilities", parent_id: null, transaction_count: 0 };
    apiMock.post.mockResolvedValue(created as never);
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/categories") return CATEGORIES as never;
      if (path === "/categories/c9") return {
        ...FOOD_DETAIL, id: "c9", name: "Utilities", subcategories: [],
        total_count: 0, total_spend: 0, total_returns: 0,
        by_merchant: {}, monthly_spend: {}, monthly_spend_rollup: {},
      } as never;
      if (path.startsWith("/cash_transactions")) return [] as never;
      return [] as never;
    });

    renderApp({ initialPath: "/categories", initialToken: "tok" });
    await screen.findByText("Food");

    fireEvent.click(screen.getByTitle("New category"));
    fireEvent.change(screen.getByPlaceholderText("Category name"), { target: { value: "Utilities" } });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/categories", { name: "Utilities", parent_id: null });
    });
    // Newly created category is selected in the detail pane
    expect(await screen.findByRole("heading", { name: "Utilities" })).toBeInTheDocument();
  });

  it("renames a category from the detail header", async () => {
    renderApp({ initialPath: "/categories#id=c1", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Food" });

    // "Rename" now lives in the "Page actions" pencil dropdown
    // (menu items render in a portal on document.body).
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /Rename/i }));
    fireEvent.change(screen.getByDisplayValue("Food"), { target: { value: "Food & Drink" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/categories/c1", { name: "Food & Drink" });
    });
  });

  // Opens the category settings dialog via the "Page actions" pencil menu.
  async function openSettingsDialog() {
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /Category settings/i }));
    await screen.findByRole("dialog");
  }

  it("reparents a category via the parent select", async () => {
    renderApp({ initialPath: "/categories#id=c1", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Food" });

    await openSettingsDialog();
    fireEvent.change(screen.getByLabelText("Parent category"), { target: { value: "c3" } });

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/categories/c1", { parent_id: "c3" });
    });
  });

  it("adds a subcategory from the detail sidebar", async () => {
    renderApp({ initialPath: "/categories#id=c1", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Food" });

    fireEvent.click(screen.getByText("Add subcategory"));
    fireEvent.change(screen.getByPlaceholderText("Subcategory name"), { target: { value: "Snacks" } });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/categories", { name: "Snacks", parent_id: "c1" });
    });
  });

  it("deletes a category after confirmation and returns to the empty state", async () => {
    renderApp({ initialPath: "/categories#id=c1", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Food" });

    // "Delete category" now lives in the "Page actions" pencil dropdown
    // (menu items render in a portal on document.body).
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /Delete category/i }));
    // Confirm in the themed dialog
    expect(await screen.findByText('Delete "Food"?')).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/categories/c1");
    });
    expect(await screen.findByText("Select a category to see details")).toBeInTheDocument();
  });
});
