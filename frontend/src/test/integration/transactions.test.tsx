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
import { quietTransactionContext } from "@/test/fixtures/transactionContext";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const TXNS = [
  {
    id: "tx-1", transaction_date: "2026-01-15", description: "STARBUCKS RESERVE",
    amount: -7.25, source: "credit_card", transaction_type: "Sale",
    merchant_id: "m1", merchant_name: "Starbucks",
    category_id: "c1", category_name: "Coffee",
    account_id: "a1", account_name: "Amex",
    created_at: "2026-01-15T10:00:00Z",
    tags: [], memo: null,
  },
  {
    id: "tx-2", transaction_date: "2026-01-16", description: "WALMART",
    amount: -42.00, source: "credit_card", transaction_type: "Sale",
    merchant_id: null, merchant_name: null,
    category_id: null, category_name: null,
    account_id: "a1", account_name: "Amex",
    created_at: "2026-01-16T10:00:00Z",
    tags: [], memo: null,
  },
];

beforeEach(() => {
  clearToken();
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
    if (path === "/cash_transactions") return TXNS as never;
    if (path.startsWith("/cash_transactions?")) return TXNS as never;
    if (path === "/cash_transactions/tx-1") return TXNS[0] as never;
    if (path === "/cash_transactions/tx-2") return TXNS[1] as never;
    if (path === "/cash_transactions/tx-1/context") return quietTransactionContext(TXNS[0]) as never;
    if (path === "/cash_transactions/tx-2/context") return quietTransactionContext(TXNS[1]) as never;
    if (path === "/merchants") return [
      { id: "m1", name: "Starbucks" },
      { id: "m2", name: "Walmart Inc" },
    ] as never;
    if (path === "/categories") return [] as never;
    if (path === "/merchants/m1") return { id: "m1", name: "Starbucks",
      monthly_spend: {}, monthly_counts: {}, monthly_income: {} } as never;
    if (path === "/categories/c1") return { id: "c1", name: "Coffee",
      parent: null, subcategories: [], total_count: 0, total_spend: 0,
      total_returns: 0, by_merchant: [], monthly_spend: {},
      monthly_spend_rollup: {} } as never;
    return [] as never;
  });
});

describe("Transactions: list + detail navigation", () => {
  it("/transactions renders rows from the API", async () => {
    renderApp({ initialPath: "/transactions", initialToken: "tok" });
    expect(await screen.findByText("Starbucks")).toBeInTheDocument();
    expect(screen.getByText("WALMART")).toBeInTheDocument();
  });

  it("/transactions/:id renders the detail view", async () => {
    renderApp({ initialPath: "/transactions/tx-1", initialToken: "tok" });
    expect(await screen.findByRole("heading", { level: 1, name: "Starbucks" })).toBeInTheDocument();
    expect(screen.getAllByText("STARBUCKS RESERVE").length).toBeGreaterThan(0);
    expect(screen.getByText("-$7.25")).toBeInTheDocument();
  });

  it("/transactions/:id shows 'Transaction not found' when the detail 404s", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/cash_transactions/missing") throw new Error("HTTP 404");
      return [] as never;
    });

    renderApp({ initialPath: "/transactions/missing", initialToken: "tok" });
    expect(await screen.findByText(/Transaction not found/i)).toBeInTheDocument();
  });
});

describe("Transactions: drill-down URL params pre-filter the table", () => {
  it("?merchant_id seeds a merchant filter pill and filters the rows", async () => {
    renderApp({ initialPath: "/transactions?merchant_id=m1", initialToken: "tok" });

    // tx-1 (Starbucks) passes — rendered in the row AND as the pill value
    // (the pill resolves the id to a name once /merchants loads)
    await waitFor(() => expect(screen.getAllByText("Starbucks").length).toBeGreaterThan(1));
    // tx-2 (no merchant) is filtered out
    expect(screen.queryByText("WALMART")).not.toBeInTheDocument();
    // Visible pill carries the field label (plus the table column header)
    expect(screen.getAllByText("Merchant").length).toBeGreaterThanOrEqual(2);
  });

  it("?start_date/?end_date seed date filters", async () => {
    renderApp({
      initialPath: "/transactions?start_date=2026-01-16&end_date=2026-01-31",
      initialToken: "tok",
    });

    expect(await screen.findByText("WALMART")).toBeInTheDocument();
    expect(screen.queryByText("Starbucks")).not.toBeInTheDocument();
    // Two date pills
    expect(screen.getAllByText("Date").length).toBeGreaterThanOrEqual(2);
  });

  it("?tag_id scopes the query server-side", async () => {
    renderApp({ initialPath: "/transactions?tag_id=t9", initialToken: "tok" });

    await screen.findByText("WALMART");
    expect(apiMock.get).toHaveBeenCalledWith(
      "/cash_transactions?tag_id=t9&limit=1000&offset=0",
      { signal: expect.any(AbortSignal) },
    );
  });
});

describe("Transactions: assign merchant from detail (no current merchant)", () => {
  it("PATCHes /cash_transactions/:id when a merchant is set on an uncategorized txn", async () => {
    apiMock.patch.mockImplementation(async (path: string, body?: unknown) => {
      if (path.startsWith("/cash_transactions/")) {
        return { ...TXNS[1], ...(body as object), merchant_name: "Starbucks" } as never;
      }
      return {} as never;
    });

    renderApp({ initialPath: "/transactions/tx-2", initialToken: "tok" });

    await screen.findByRole("heading", { level: 1, name: "WALMART" });

    fireEvent.click(screen.getByRole("button", { name: "Edit merchant" }));

    const combobox = await screen.findByPlaceholderText(/Search or create merchant/i);
    fireEvent.focus(combobox);
    fireEvent.mouseDown(await screen.findByText("Starbucks"));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/tx-2", { merchant_id: "m1" });
    });
  });
});

describe("Transactions: detail edit patches caches in place (no list refetch)", () => {
  it("writes the updated row into the cache and only invalidates aggregates", async () => {
    apiMock.patch.mockImplementation(async (path: string, body?: unknown) => {
      if (path.startsWith("/cash_transactions/")) {
        return { ...TXNS[1], ...(body as object), merchant_name: "Starbucks" } as never;
      }
      return {} as never;
    });

    const { client } = renderApp({ initialPath: "/transactions/tx-2", initialToken: "tok" });
    const invalidateSpy = vi.spyOn(client, "invalidateQueries");

    await screen.findByRole("heading", { level: 1, name: "WALMART" });
    fireEvent.click(screen.getByRole("button", { name: "Edit merchant" }));

    const combobox = await screen.findByPlaceholderText(/Search or create merchant/i);
    fireEvent.focus(combobox);
    fireEvent.mouseDown(await screen.findByText("Starbucks"));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/tx-2", { merchant_id: "m1" });
      // The returned row is patched into the detail cache in place…
      expect(client.getQueryData(["cash_transactions", "tx-2"])).toMatchObject({
        id: "tx-2",
        merchant_id: "m1",
        merchant_name: "Starbucks",
      });
      // …aggregate views are marked stale…
      expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ["merchants"] });
      expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ["cashflow"] });
      // …but the transaction lists are NOT refetched wholesale (that used to
      // re-pull every 1000-row page of the infinite query on each edit).
      expect(invalidateSpy).not.toHaveBeenCalledWith({ queryKey: ["cash_transactions"] });
    });
  });
});
