import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen } from "@testing-library/react";
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
import { quietTransactionContext } from "@/test/fixtures/transactionContext";
import type { CashTransaction } from "@/api/types";

const apiMock = vi.mocked(api);

const TXN: CashTransaction = {
  id: "tx-9", source: "manual", transaction_date: "2026-06-15",
  transfer_id: null, post_date: "2026-06-15", description: "MYSTERY CHARGE",
  amount: -42, transaction_type: "Sale",
  category_id: null, category_name: null,
  merchant_id: null, merchant_name: null,
  account_id: "a1", account_name: "Checking",
  balance: null, memo: null,
  loan_id: null, loan_name: null,
  tags: [],
  created_at: "2026-06-15T12:00:00Z",
};

const TXN_ACTIVITY = {
  entries: [
    { id: "e9", occurred_at: "2026-06-15T12:00:00Z", source: "import", event: "import.row_created",
      severity: "info", summary: "Imported from chase.csv", payload: { row: 12 },
      subject_type: "CashTransaction", subject_id: "tx-9", trace_id: null,
      caused_by_type: null, caused_by_id: null, duration_ms: null },
    { id: "e10", occurred_at: "2026-06-15T12:01:00Z", source: "merchant_rules", event: "rule.applied",
      severity: "info", summary: "Rule 'Groceries' assigned category", payload: null,
      subject_type: "CashTransaction", subject_id: "tx-9", trace_id: null,
      caused_by_type: null, caused_by_id: null, duration_ms: 45 },
  ],
  meta: { page: 1, per_page: 50, total: 2 },
};

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
    if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                 household: { id: "h1", name: "H", role: "admin" } } as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
    if (path === "/cash_transactions/tx-9") return TXN as never;
    if (path === "/cash_transactions/tx-9/context") return quietTransactionContext(TXN) as never;
    if (path === "/activity?subject_type=CashTransaction&subject_id=tx-9&page=1") return TXN_ACTIVITY as never;
    return [] as never;
  });
});

describe("Transaction detail: activity section", () => {
  it("queries subject-scoped activity and renders the entries", async () => {
    renderApp({ initialPath: "/transactions/tx-9", initialToken: "tok" });

    expect(await screen.findByText("Imported from chase.csv")).toBeInTheDocument();
    expect(screen.getByText("Rule 'Groceries' assigned category")).toBeInTheDocument();
    expect(screen.getByText("Import")).toBeInTheDocument();
    expect(screen.getByText("Merchant rules")).toBeInTheDocument();
    expect(screen.getByText("45ms")).toBeInTheDocument();

    expect(apiMock.get).toHaveBeenCalledWith("/activity?subject_type=CashTransaction&subject_id=tx-9&page=1");
  });

  it("expands an entry to its payload JSON", async () => {
    renderApp({ initialPath: "/transactions/tx-9", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /Imported from chase\.csv/ }));

    expect(await screen.findByText(/"row": 12/)).toBeInTheDocument();
  });

  it("shows an empty state when the transaction has no activity", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      if (path === "/cash_transactions/tx-9") return TXN as never;
      if (path === "/cash_transactions/tx-9/context") return quietTransactionContext(TXN) as never;
    if (path === "/cash_transactions/tx-9/context") return quietTransactionContext(TXN) as never;
      if (path.startsWith("/activity?")) return { entries: [], meta: { page: 1, per_page: 50, total: 0 } } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/transactions/tx-9", initialToken: "tok" });

    expect(await screen.findByText("No activity recorded for this transaction.")).toBeInTheDocument();
  });
});
