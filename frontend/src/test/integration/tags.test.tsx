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
import type { SpendBreakdownData, Tag, TagDetail } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const TAGS: Tag[] = [
  { id: "t1", name: "vacation", transaction_count: 8, total_spend: 1450.75 },
  { id: "t2", name: "reimbursable", transaction_count: 3, total_spend: 210 },
  { id: "t3", name: "gifts" }, // no counts — row falls back to 0
];

const VACATION_DETAIL: TagDetail = {
  id: "t1",
  name: "vacation",
  total_count: 8,
  total_spend: 1450.75,
  total_returns: 0,
  by_category: { Travel: 900.25, Dining: 550.5 },
  monthly_spend: { "2026-06": 300, "2026-05": 150 },
};

/** The detail page's spend chart feeds itself from the tag-scoped breakdown. */
const SPEND_BREAKDOWN: SpendBreakdownData = {
  from: "2026-05-01",
  to: "2026-06-30",
  monthly_spend: { "2026-05-01": 150, "2026-06-01": 300 },
  monthly_spend_common: { "2026-05-01": 150, "2026-06-01": 300 },
  category: {
    series: [{ id: "cat-travel", name: "Travel" }],
    months: { "2026-05-01": { "cat-travel": 150 }, "2026-06-01": { "cat-travel": 300 } },
  },
  category_common: {
    series: [{ id: "cat-travel", name: "Travel" }],
    months: { "2026-05-01": { "cat-travel": 150 }, "2026-06-01": { "cat-travel": 300 } },
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
    if (path === "/tags") return TAGS as never;
    if (path === "/tags/t1") return VACATION_DETAIL as never;
    if (path.startsWith("/cashflow/spend_breakdown")) return SPEND_BREAKDOWN as never;
    if (path.startsWith("/cash_transactions")) return [] as never;
    return [] as never;
  });
});

describe("Tags: list", () => {
  it("renders tags with transaction counts and an empty detail prompt", async () => {
    renderApp({ initialPath: "/tags", initialToken: "tok" });

    expect(await screen.findByText("vacation")).toBeInTheDocument();
    expect(screen.getByText("reimbursable")).toBeInTheDocument();
    expect(screen.getByText("gifts")).toBeInTheDocument();
    expect(screen.getByText("8")).toBeInTheDocument();
    expect(screen.getByText("3")).toBeInTheDocument();
    expect(screen.getByText("0")).toBeInTheDocument(); // gifts has no count

    expect(screen.getByText("Select a tag to see details")).toBeInTheDocument();
  });

  it("filters tags via search and shows an empty state when nothing matches", async () => {
    renderApp({ initialPath: "/tags", initialToken: "tok" });
    await screen.findByText("vacation");

    const input = screen.getByPlaceholderText(/Search tags/);
    fireEvent.change(input, { target: { value: "reim" } });

    expect(screen.getByText("reimbursable")).toBeInTheDocument();
    expect(screen.queryByText("vacation")).not.toBeInTheDocument();

    fireEvent.change(input, { target: { value: "zzz" } });
    expect(screen.getByText("No tags match the current filters.")).toBeInTheDocument();
  });

  it("shows the empty state when there are no tags at all", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/tags", initialToken: "tok" });
    expect(await screen.findByText("No tags yet.")).toBeInTheDocument();
  });
});

describe("Tags: detail", () => {
  it("selecting a tag with Enter from search shows its detail panel", async () => {
    renderApp({ initialPath: "/tags", initialToken: "tok" });
    await screen.findByText("vacation");

    const input = screen.getByPlaceholderText(/Search tags/);
    fireEvent.change(input, { target: { value: "vaca" } });
    fireEvent.keyDown(input, { key: "Enter" });

    expect(await screen.findByRole("heading", { name: "vacation" })).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/tags/t1");
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?tag_id=t1");
  });

  it("renders stats and the by-category breakdown", async () => {
    renderApp({ initialPath: "/tags#id=t1", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "vacation" })).toBeInTheDocument();
    expect(screen.getByText("$1,450.75")).toBeInTheDocument(); // total spend stat

    // By Category table
    expect(screen.getByText("Travel")).toBeInTheDocument();
    expect(screen.getByText("$900.25")).toBeInTheDocument();
    expect(screen.getByText("Dining")).toBeInTheDocument();
    expect(screen.getByText("$550.50")).toBeInTheDocument();
  });

  it("feeds the spend chart from the tag-scoped breakdown, with in-card controls", async () => {
    renderApp({ initialPath: "/tags#id=t1", initialToken: "tok" });
    await screen.findByRole("heading", { name: "vacation" });

    // Self-sufficient chart: one endpoint, scoped to the tag and the default 1y window.
    const { from, to } = timeframeRange("1y");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/spend_breakdown?from=${from}&to=${to}&tag_id=t1`);
    });

    // This page has no scoping header, so the chart carries its own controls.
    expect(screen.getByText("Monthly Spend")).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Spend split" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Spend series" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Timeframe" })).toBeInTheDocument();
  });

  it("shows an error message when the detail request fails", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/tags") return TAGS as never;
      if (path === "/tags/t1") throw new Error("HTTP 500");
      return [] as never;
    });

    renderApp({ initialPath: "/tags#id=t1", initialToken: "tok" });
    expect(await screen.findByText("Failed to load tag")).toBeInTheDocument();
  });
});

describe("Tags: create", () => {
  it("creates a tag via the inline form and selects it", async () => {
    apiMock.post.mockResolvedValue({ id: "t9", name: "travel" } as never);
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/tags") return TAGS as never;
      if (path === "/tags/t9") return {
        id: "t9", name: "travel", total_count: 0, total_spend: 0, total_returns: 0,
        by_category: {}, monthly_spend: {},
      } as never;
      if (path.startsWith("/cash_transactions")) return [] as never;
      return [] as never;
    });

    renderApp({ initialPath: "/tags", initialToken: "tok" });
    await screen.findByText("vacation");

    fireEvent.click(screen.getByTitle("New tag"));
    fireEvent.change(screen.getByPlaceholderText("Tag name"), { target: { value: "travel" } });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/tags", { name: "travel" });
    });
    // The new tag becomes the selected detail
    expect(await screen.findByRole("heading", { name: "travel" })).toBeInTheDocument();
  });

  it("does not submit when the name is blank", async () => {
    renderApp({ initialPath: "/tags", initialToken: "tok" });
    await screen.findByText("vacation");

    fireEvent.click(screen.getByTitle("New tag"));
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    expect(await screen.findByText("Name is required")).toBeInTheDocument();
    expect(apiMock.post).not.toHaveBeenCalled();
  });
});
