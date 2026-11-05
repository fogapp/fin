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
import type { CashTransaction, TransactionContext } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const TXN: CashTransaction = {
  id: "tx-2", source: "credit_card", transaction_date: "2026-06-15",
  transfer_id: null, post_date: "2026-06-17", description: "STARBUCKS #1234",
  amount: -18.5, transaction_type: "Sale",
  category_id: "c1", category_name: "Coffee",
  merchant_id: "m1", merchant_name: "Starbucks",
  account_id: "a1", account_name: "Amex Card",
  balance: 1200.34, memo: "Team offsite lattes",
  loan_id: null, loan_name: null,
  tags: [{ id: "t1", name: "work" }, { id: "t2", name: "reimbursable" }],
  created_at: "2026-06-15T12:00:00Z",
};

const BARE_TXN: CashTransaction = {
  ...TXN,
  id: "tx-9", description: "MYSTERY CHARGE", post_date: "2026-06-15",
  merchant_id: null, merchant_name: null, category_id: null, category_name: null,
  balance: null, memo: null, tags: [],
};

const MERCHANTS = [
  { id: "m1", name: "Starbucks", category_id: null, category_name: null, notes: null, transaction_count: 34, excluded: false },
  { id: "m2", name: "Peets Coffee", category_id: null, category_name: null, notes: null, transaction_count: 5, excluded: false },
];

const CATEGORIES = [
  { id: "c1", name: "Coffee", parent_id: null, transaction_count: 87 },
  { id: "c2", name: "Dining", parent_id: null, transaction_count: 40 },
  { id: "c3", name: "Lattes", parent_id: "c1", transaction_count: 12 },
];

const row = (id: string, date: string, amount: number, extra: Partial<TransactionContext["history"]["rows"][number]> = {}) => ({
  id, transaction_date: date, description: "STARBUCKS #1234", amount, account_name: "Amex Card",
  merchant_name: "Starbucks", category_id: "c1", category_name: "Coffee", transfer_id: null, ...extra,
});

const CONTEXT: TransactionContext = {
  history: {
    basis: "merchant", label: "Starbucks", total: 4,
    rows: [
      row("tx-0", "2026-04-15", -8.5),
      row("tx-1", "2026-05-15", -9),
      row("tx-2", "2026-06-15", -18.5),
      row("tx-3", "2026-06-28", -8.75, { category_id: null, category_name: null }),
    ],
  },
  stats: {
    count: 4, ordinal: 3, median: 8.88, p25: 8.69, p75: 11.38, min: 8.5, max: 18.5,
    percentile: 1, ratio_to_median: 2.08, first_date: "2026-04-15", last_date: "2026-06-28",
    trailing_year_total: 44.75, trailing_year_count: 4,
  },
  cadence: null,
  series: null,
  treatment: { spend: true, income: false, budget: true, merchant_excluded: false },
  budget: {
    scope: "line", category_id: "c1", category_name: "Coffee", period: "monthly", month: "2026-06",
    available: 60, actual: 36.5, before: 18, contribution: 18.5, remaining: 23.5, typical: 30,
    history: [
      { month: "2026-05", planned: 60, actual: 40 },
      { month: "2026-06", planned: 60, actual: 36.5 },
    ],
  },
  duplicates: [],
  related: [],
  same_day: { total: 1, rows: [row("tx-7", "2026-06-15", -62.1, { description: "WHOLE FOODS", merchant_name: "Whole Foods", category_name: "Groceries" })] },
  suggested_category: null,
};

const CADENCE: NonNullable<TransactionContext["cadence"]> = {
  granularity: "month", quantity: 1, anchor: { day_of_month: 15 }, description: "Monthly on the 15th",
  confidence: 0.9, hit_rate: 1, matched_count: 3, missed_count: 0, includes_transaction: true,
  average_amount: 12, next_expected_date: "2026-07-15", matched_ids: ["tx-0", "tx-1", "tx-2"],
};

let context: TransactionContext;

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());
  context = structuredClone(CONTEXT);

  apiMock.post.mockResolvedValue({ id: "s1", name: "Starbucks", updated: 1 } as never);
  apiMock.delete.mockResolvedValue({} as never);
  apiMock.patch.mockImplementation(async (path: string, body?: unknown) => {
    if (path.startsWith("/cash_transactions/")) return { ...TXN, ...(body as object) } as never;
    return {} as never;
  });

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/cash_transactions/tx-2") return TXN as never;
    if (path === "/cash_transactions/tx-9") return BARE_TXN as never;
    if (path.endsWith("/context")) return context as never;
    if (path === "/merchants") return MERCHANTS as never;
    if (path === "/categories") return CATEGORIES as never;
    if (path.startsWith("/activity?")) return { entries: [], page: 1, total_pages: 1 } as never;
    if (path.startsWith("/transfers/for_transaction")) return null as never;
    if (path.startsWith("/subscriptions/")) return { occurrences: [] } as never;
    return [] as never;
  });
});

const open = async (path = "/transactions/tx-2", heading = "Starbucks") => {
  renderApp({ initialPath: path, initialToken: "tok" });
  await screen.findByRole("heading", { level: 1, name: heading });
};

describe("Transaction page: the story", () => {
  it("leads with who, how much, where and when, plus what stands out", async () => {
    await open();

    expect(screen.getAllByText("-$18.50").length).toBeGreaterThan(0);
    expect(screen.getByTitle('Search Google for "STARBUCKS #1234"')).toHaveAttribute("target", "_blank");
    expect(screen.getByRole("link", { name: "Amex Card" })).toHaveAttribute("href", "/accounts#id=a1");
    expect(await screen.findByRole("button", { name: /2\.1× your usual/ })).toBeInTheDocument();
  });

  it("places the charge in its merchant history", async () => {
    await open();

    expect(await screen.findByText("Charge 3 of 4 at Starbucks — 2.1× the usual $8.88.")).toBeInTheDocument();
    expect(screen.getByRole("img", { name: /4 charges over time/ })).toBeInTheDocument();
    // The neighbors list links to the other charges and marks this one.
    expect(screen.getAllByRole("link").some((a) => a.getAttribute("href") === "/transactions/tx-1")).toBe(true);
    expect(screen.getByText("This transaction").closest("[aria-current]")).not.toBeNull();
  });

  it("says what the charge did to its budget line", async () => {
    await open();

    expect(await screen.findByText("This used 31% of Coffee in June, leaving $23.50.")).toBeInTheDocument();
    expect(screen.getByRole("img", { name: /\$18\.00 spent before, \$18\.50 this charge, of \$60\.00/ })).toBeInTheDocument();
  });

  it("lists the rest of the day", async () => {
    await open();

    expect(await screen.findByText(/1 other transaction the same day — \$80\.60 spent in all/)).toBeInTheDocument();
    expect(screen.getByText("Whole Foods")).toBeInTheDocument();
  });

  it("shows the subscription a charge belongs to and lets a suggested one be accepted", async () => {
    context.series = {
      id: "s1", name: "Starbucks Club", status: "suggested", kind: "subscription",
      cadence_description: "Monthly on the 15th", next_expected_date: "2026-07-15",
      average_amount: 12, annual_equivalent: 144, includes_transaction: true,
    };
    await open();

    expect(await screen.findByText("Fin thinks this is a subscription, charged monthly on the 15th.")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Track it" }));
    await waitFor(() => expect(apiMock.post).toHaveBeenCalledWith("/subscriptions/s1/accept", {}));
  });
});

describe("Transaction page: detecting a subscription", () => {
  it("tracks a detected cadence with its earlier charges as history", async () => {
    context.cadence = CADENCE;
    await open();

    expect(await screen.findByText("This looks like a charge that repeats monthly on the 15th.")).toBeInTheDocument();
    // The section's call to action (the rail offers the same dialog).
    fireEvent.click(screen.getAllByRole("button", { name: /Track as subscription/ })[0]);
    expect(await screen.findByText(/Fin found 3 charges monthly on the 15th/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Track subscription" }));

    await waitFor(() => expect(apiMock.post).toHaveBeenCalledWith("/subscriptions", expect.objectContaining({
      name: "Starbucks", granularity: "month", quantity: 1, anchor: { day_of_month: 15 },
      average_amount: 12, merchant_id: "m1", account_id: "a1",
      cash_transaction_id: "tx-2", history_transaction_ids: ["tx-0", "tx-1"],
    })));
  });
});

describe("Transaction page: decisions", () => {
  it("offers the category the merchant's other charges agree on", async () => {
    context.suggested_category = { category_id: "c2", category_name: "Dining", count: 3, of: 3 };
    await open();

    fireEvent.click(await screen.findByRole("button", { name: "Use Dining" }));
    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/tx-2", { category_id: "c2" }));
  });

  it("applies this category to the merchant's uncategorized charges", async () => {
    await open();

    fireEvent.click(await screen.findByRole("button", { name: "Make them Coffee too" }));
    await waitFor(() => expect(apiMock.post).toHaveBeenCalledWith("/cash_transactions/bulk_update", { ids: ["tx-3"], category_id: "c1" }));
  });

  it("deletes a possible duplicate only after confirming", async () => {
    context.duplicates = [{ ...row("tx-5", "2026-06-16", -18.5), date_diff: 1 }];
    await open();

    expect(await screen.findByText(/Possible duplicate: the same \$18\.50 charge on Amex Card, 1 day later/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Delete this one/ }));
    expect(apiMock.delete).not.toHaveBeenCalled();
    fireEvent.click(await screen.findByRole("button", { name: "Delete" }));
    await waitFor(() => expect(apiMock.delete).toHaveBeenCalledWith("/cash_transactions/tx-2"));
  });

  it("leaves a one-off purchase out of budgets", async () => {
    await open();

    expect(await screen.findByText("Counted in budgets")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Leave out" }));
    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/tx-2", { budget_excluded: true }));
  });
});

describe("Transaction page: editing details", () => {
  // MerchantCombobox fires onChange("") as soon as the typed text no longer
  // matches the selected merchant's name. Typing to search must NOT save —
  // saving happens only when the user picks a suggestion or explicitly clears.
  it("does not save while typing to search; picking a suggestion PATCHes the picked id", async () => {
    await open();

    fireEvent.click(screen.getByRole("button", { name: "Edit merchant" }));
    const combobox = await screen.findByPlaceholderText("Search or create merchant…");
    await waitFor(() => expect(combobox).toHaveValue("Starbucks"));

    fireEvent.change(combobox, { target: { value: "Pee" } });
    const txnPatches = () => apiMock.patch.mock.calls.filter(([path]) => String(path).startsWith("/cash_transactions/"));
    expect(txnPatches()).toHaveLength(0);

    fireEvent.mouseDown(await screen.findByText("Peets Coffee"));
    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/tx-2", { merchant_id: "m2" }));
    await waitFor(() => expect(screen.queryByPlaceholderText("Search or create merchant…")).not.toBeInTheDocument());
  });

  it("clears the merchant only from the explicit button", async () => {
    await open();

    fireEvent.click(screen.getByRole("button", { name: "Edit merchant" }));
    fireEvent.click(await screen.findByRole("button", { name: "Clear merchant" }));
    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/tx-2", { merchant_id: null }));
  });

  it("does not clear the category while typing; picking one PATCHes it", async () => {
    await open();

    fireEvent.click(screen.getByRole("button", { name: "Edit category" }));
    const combobox = await screen.findByRole("textbox", { name: "Category" });
    await waitFor(() => expect(combobox).toHaveValue("Coffee"));
    fireEvent.focus(combobox);
    fireEvent.change(combobox, { target: { value: "Din" } });
    expect(apiMock.patch.mock.calls.filter(([p]) => String(p).startsWith("/cash_transactions/"))).toHaveLength(0);

    fireEvent.mouseDown(await screen.findByText("Dining"));
    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/tx-2", { category_id: "c2" }));
  });

  it("saves the note on blur", async () => {
    await open();

    const note = screen.getByRole("textbox", { name: "Note" });
    expect(note).toHaveValue("Team offsite lattes");
    fireEvent.change(note, { target: { value: "Client coffee" } });
    fireEvent.blur(note);
    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/tx-2", { memo: "Client coffee" }));
  });

  it("works for a bare transaction with nothing to compare against", async () => {
    context = {
      ...CONTEXT,
      history: { basis: "description", label: "MYSTERY CHARGE", total: 1, rows: [row("tx-9", "2026-06-15", -18.5, { description: "MYSTERY CHARGE" })] },
      stats: null, budget: { ...CONTEXT.budget!, scope: "everything_else", category_id: null, category_name: null, available: null, remaining: null, history: [] },
      same_day: { total: 0, rows: [] },
    };
    await open("/transactions/tx-9", "MYSTERY CHARGE");

    expect(await screen.findByText("The first charge with this description.")).toBeInTheDocument();
    expect(screen.getByText(/No budget covers this/)).toBeInTheDocument();
    expect(screen.queryByRole("img", { name: /charges over time/ })).not.toBeInTheDocument();
  });
});
