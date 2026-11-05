import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, fireEvent, waitFor, within } from "@testing-library/react";
import { renderWithRouter } from "@/test/queryClient";
import { formatDate } from "@/lib/utils";
import type { CashTransaction } from "@/api/types";

vi.mock("@/api/client", () => ({
  api: {
    get: vi.fn((path: string) => {
      if (path === "/preferences") return Promise.resolve({ data: {} });
      if (path.startsWith("/transfers/for_transaction")) return Promise.resolve(null);
      if (path === "/tags") return Promise.resolve([{ id: "tg1", name: "travel" }]);
      if (path.startsWith("/cash_transactions/transfer_search")) {
        return Promise.resolve([
          {
            id: "cand1",
            description: "TRANSFER IN",
            account_name: "Checking",
            transaction_date: "2026-01-16",
            amount: 12.5,
          },
        ]);
      }
      if (path === "/categories") {
        return Promise.resolve([
          { id: "c1", name: "Food", parent_id: null, transaction_count: 0 },
        ]);
      }
      return Promise.resolve([]);
    }),
    post: vi.fn(() => Promise.resolve({ id: "v-new", name: "x", conditions: [], match_all: true, created_at: "" })),
    patch: vi.fn(() => Promise.resolve({})),
    delete: vi.fn(() => Promise.resolve(undefined)),
  },
}));

vi.mock("@/lib/csv", async () => {
  const actual = await vi.importActual<typeof import("@/lib/csv")>("@/lib/csv");
  return { ...actual, downloadCsv: vi.fn() };
});

import { api } from "@/api/client";
import { TransactionTable } from "./TransactionTable";
import { amountColor } from "@/lib/transactions";
import { downloadCsv } from "@/lib/csv";

const mockedApi = vi.mocked(api);

function tx(overrides: Partial<CashTransaction>): CashTransaction {
  return {
    id: "x",
    transaction_date: "2026-01-01",
    description: "X",
    amount: 0,
    source: "credit_card",
    transaction_type: "Sale",
    ...overrides,
  } as CashTransaction;
}

describe("TransactionTable — amountColor helper", () => {
  it("returns green for 'Return' transactions regardless of source", () => {
    expect(amountColor(tx({ transaction_type: "Return", source: "credit_card" }))).toBe("text-positive");
    expect(amountColor(tx({ transaction_type: "Return", source: "bank", amount: -10 }))).toBe("text-positive");
  });

  it("returns green for bank transactions with a positive amount (credit/deposit)", () => {
    expect(amountColor(tx({ source: "bank", transaction_type: "Credit", amount: 100 }))).toBe("text-positive");
  });

  it("returns empty string for negative bank transactions (debits)", () => {
    expect(amountColor(tx({ source: "bank", transaction_type: "Debit", amount: -50 }))).toBe("");
  });

  it("returns empty string for credit-card Sale transactions", () => {
    expect(amountColor(tx({ source: "credit_card", transaction_type: "Sale", amount: -42.50 }))).toBe("");
  });

  it("returns empty string for credit-card Payment transactions (positive amount)", () => {
    expect(amountColor(tx({ source: "credit_card", transaction_type: "Payment", amount: 100 }))).toBe("");
  });
});

// ── Component tests ───────────────────────────────────────────────────────────

let seq = 0;
function makeTx(overrides: Partial<CashTransaction> = {}): CashTransaction {
  seq += 1;
  return {
    id: `t-${seq}`,
    source: "credit_card",
    transaction_date: "2026-01-15",
    transfer_id: null,
    post_date: null,
    description: `CARD PURCHASE ${seq}`,
    amount: -12.5,
    transaction_type: "Sale",
    category_id: null,
    category_name: null,
    merchant_id: null,
    merchant_name: null,
    account_id: null,
    account_name: null,
    balance: null,
    memo: null,
    loan_id: null,
    loan_name: null,
    tags: [],
    created_at: "2026-01-15T00:00:00Z",
    ...overrides,
  };
}

/** Text of each transaction body row (skips loading/header rows). */
function rowTexts(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll("tbody tr")).map((r) => r.textContent ?? "");
}

/** The checkbox column is hidden by default; reveal it before selecting rows. */
function revealCheckboxes() {
  fireEvent.click(screen.getByRole("button", { name: "Show selection checkboxes" }));
}

beforeEach(() => {
  vi.clearAllMocks();
  localStorage.clear();
  sessionStorage.clear();
  // Skip usePreferences' one-time localStorage migration.
  localStorage.setItem("prefs-migrated-v1", "1");
  // Keep row-level assertions simple by default: no group headers.
  localStorage.setItem("txn-default-group-by", JSON.stringify("none"));
  window.location.hash = "";
});

describe("TransactionTable — rendering", () => {
  it("shows an empty state when there are no transactions", () => {
    renderWithRouter(<TransactionTable transactions={[]} />);
    expect(screen.getByText("No transactions yet.")).toBeInTheDocument();
  });

  it("renders date, merchant (combined column), and formatted amount", () => {
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ merchant_name: "Starbucks", amount: -4.5, transaction_date: "2026-01-15" }),
        ]}
      />,
    );
    expect(screen.getByText("Starbucks")).toBeInTheDocument();
    expect(screen.getByText("-$4.50")).toBeInTheDocument();
    expect(screen.getByText(formatDate("2026-01-15"))).toBeInTheDocument();
  });

  it("falls back to a code-styled description when there is no merchant", () => {
    renderWithRouter(
      <TransactionTable transactions={[makeTx({ description: "POS 1234 ACME", merchant_name: null })]} />,
    );
    const el = screen.getByText("POS 1234 ACME");
    expect(el.tagName).toBe("CODE");
  });

  it("substitutes loan_name for the description when present", () => {
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ loan_name: "Mortgage 2024", merchant_name: "Chase", description: "LOAN PAYMENT" }),
        ]}
      />,
    );
    expect(screen.getByText("Mortgage 2024")).toBeInTheDocument();
    expect(screen.queryByText("LOAN PAYMENT")).toBeNull();
    expect(screen.queryByText("Chase")).toBeNull();
  });

  it("renders tag chips and the memo note under the description", () => {
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({
            merchant_name: "Delta",
            tags: [{ id: "tag1", name: "vacation" }, { id: "tag2", name: "work" }],
            memo: "reimbursable",
          }),
        ]}
      />,
    );
    expect(screen.getByText("vacation")).toBeInTheDocument();
    expect(screen.getByText("work")).toBeInTheDocument();
    expect(screen.getByText("reimbursable")).toBeInTheDocument();
  });

  it("honors the columns prop", () => {
    renderWithRouter(
      <TransactionTable
        transactions={[makeTx({ merchant_name: "Starbucks", category_name: "Coffee" })]}
        columns={["date", "amount"]}
      />,
    );
    expect(screen.getByRole("columnheader", { name: /Date/ })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: /Amount/ })).toBeInTheDocument();
    expect(screen.queryByRole("columnheader", { name: "Category" })).toBeNull();
    expect(screen.queryByText("Starbucks")).toBeNull();
    expect(screen.queryByText("Coffee")).toBeNull();
  });

  it("hides transfer-linked transactions by default", () => {
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ merchant_name: "Visible" }),
          makeTx({ merchant_name: "Hidden transfer", transfer_id: "tr-1" }),
        ]}
      />,
    );
    expect(screen.getByText("Visible")).toBeInTheDocument();
    expect(screen.queryByText("Hidden transfer")).toBeNull();
    expect(screen.getByText("1 result")).toBeInTheDocument();
  });
});

describe("TransactionTable — CSV export", () => {
  it("downloads the currently visible rows as CSV", () => {
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ merchant_name: "Starbucks", amount: -4.5 }),
          makeTx({ merchant_name: "Costco", amount: -180 }),
        ]}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Export CSV" }));

    expect(downloadCsv).toHaveBeenCalledTimes(1);
    const [filename, csv] = vi.mocked(downloadCsv).mock.calls[0];
    expect(filename).toMatch(/^transactions-\d{4}-\d{2}-\d{2}\.csv$/);
    expect(csv).toContain("Starbucks");
    expect(csv).toContain("Costco");
    expect(csv.split("\n")).toHaveLength(3); // header + 2 rows
  });

  it("exports only the filtered rows after a search", async () => {
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ merchant_name: "Starbucks", amount: -4.5 }),
          makeTx({ merchant_name: "Costco", amount: -180 }),
        ]}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Search" }));
    fireEvent.change(screen.getByPlaceholderText("Search…"), { target: { value: "costco" } });
    await waitFor(() => expect(screen.getByText("1 result")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "Export CSV" }));

    const [, csv] = vi.mocked(downloadCsv).mock.calls[0];
    expect(csv).toContain("Costco");
    expect(csv).not.toContain("Starbucks");
  });
});

describe("TransactionTable — sorting", () => {
  it("sorts by date descending by default and toggles on header click", () => {
    const { container } = renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ merchant_name: "OLD", transaction_date: "2026-01-01" }),
          makeTx({ merchant_name: "NEW", transaction_date: "2026-03-01" }),
          makeTx({ merchant_name: "MID", transaction_date: "2026-02-01" }),
        ]}
      />,
    );
    let rows = rowTexts(container);
    expect(rows[0]).toContain("NEW");
    expect(rows[2]).toContain("OLD");

    fireEvent.click(screen.getByRole("button", { name: "Date" }));
    rows = rowTexts(container);
    expect(rows[0]).toContain("OLD");
    expect(rows[2]).toContain("NEW");
  });

  it("switches the primary sort to amount when that header is clicked", () => {
    const { container } = renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ merchant_name: "SMALL", amount: -5 }),
          makeTx({ merchant_name: "BIG", amount: 100 }),
          makeTx({ merchant_name: "NEG", amount: -50 }),
        ]}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Amount" }));
    let rows = rowTexts(container);
    expect(rows[0]).toContain("BIG"); // desc: largest first
    expect(rows[2]).toContain("NEG");

    fireEvent.click(screen.getByRole("button", { name: "Amount" }));
    rows = rowTexts(container);
    expect(rows[0]).toContain("NEG"); // asc
  });
});

describe("TransactionTable — grouping", () => {
  it("renders month group headers with counts and collapses on click", () => {
    localStorage.setItem("txn-default-group-by", JSON.stringify("month"));
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ merchant_name: "JanA", transaction_date: "2026-01-10" }),
          makeTx({ merchant_name: "JanB", transaction_date: "2026-01-20" }),
          makeTx({ merchant_name: "Feb", transaction_date: "2026-02-10" }),
        ]}
      />,
    );
    expect(screen.getByText("January 2026")).toBeInTheDocument();
    expect(screen.getByText("February 2026")).toBeInTheDocument();
    // January header shows its row count
    const janHeader = screen.getByText("January 2026").closest("tr")!;
    expect(janHeader).toHaveTextContent("2");

    fireEvent.click(screen.getByText("January 2026"));
    expect(screen.queryByText("JanA")).toBeNull();
    expect(screen.queryByText("JanB")).toBeNull();
    expect(screen.getByText("Feb")).toBeInTheDocument();

    fireEvent.click(screen.getByText("January 2026"));
    expect(screen.getByText("JanA")).toBeInTheDocument();
  });
});

describe("TransactionTable — filters & search", () => {
  it("restores filters from sessionStorage and applies them", () => {
    sessionStorage.setItem(
      "txn_filters:/",
      JSON.stringify([{ _key: 9, field: "description", operator: "contains", value: "starbucks" }]),
    );
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ description: "STARBUCKS #12" }),
          makeTx({ description: "AMAZON MKTPL" }),
        ]}
      />,
    );
    expect(screen.getByText("STARBUCKS #12")).toBeInTheDocument();
    expect(screen.queryByText("AMAZON MKTPL")).toBeNull();
    expect(screen.getByText("1 result")).toBeInTheDocument();
    // Filter pill is visible
    expect(screen.getByText("contains")).toBeInTheDocument();
    expect(screen.getByText("starbucks")).toBeInTheDocument();
    // ...and the filters were re-persisted
    expect(sessionStorage.getItem("txn_filters:/")).toContain("starbucks");
  });

  it("filters rows by account", () => {
    sessionStorage.setItem(
      "txn_filters:/",
      JSON.stringify([{ _key: 9, field: "account_id", operator: "equals", value: "acct-1" }]),
    );
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ description: "CHECKING TXN", account_id: "acct-1", account_name: "Checking" }),
          makeTx({ description: "SAVINGS TXN", account_id: "acct-2", account_name: "Savings" }),
        ]}
      />,
    );
    expect(screen.getByText("CHECKING TXN")).toBeInTheDocument();
    expect(screen.queryByText("SAVINGS TXN")).toBeNull();
    expect(screen.getByText("1 result")).toBeInTheDocument();
  });

  it("filters rows through the search box", () => {
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ merchant_name: "Amazon", description: "AMAZON" }),
          makeTx({ merchant_name: "Costco", description: "COSTCO" }),
        ]}
      />,
    );
    fireEvent.click(screen.getByTitle("Search"));
    fireEvent.change(screen.getByPlaceholderText("Search…"), { target: { value: "amazon" } });
    expect(screen.getByText("Amazon")).toBeInTheDocument();
    expect(screen.queryByText("Costco")).toBeNull();
    expect(screen.getByText("1 result")).toBeInTheDocument();
  });
});

describe("TransactionTable — row selection & bulk actions", () => {
  it("selects rows, supports select-all, and clears", () => {
    renderWithRouter(
      <TransactionTable transactions={[makeTx(), makeTx(), makeTx()]} />,
    );
    revealCheckboxes();
    const [selectAll, ...rowBoxes] = screen.getAllByRole("checkbox");
    fireEvent.click(rowBoxes[0]);
    expect(screen.getByText("1 selected")).toBeInTheDocument();

    fireEvent.click(selectAll);
    expect(screen.getByText("3 selected")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Clear" }));
    expect(screen.getByText("0 selected")).toBeInTheDocument(); // bar collapses but keeps content
  });

  it("hides the checkbox column by default and drops the selection when toggled off", () => {
    renderWithRouter(
      <TransactionTable transactions={[makeTx(), makeTx(), makeTx()]} />,
    );
    expect(screen.queryAllByRole("checkbox")).toHaveLength(0);

    revealCheckboxes();
    expect(screen.getAllByRole("checkbox")).toHaveLength(4); // select-all + 3 rows

    fireEvent.click(screen.getAllByRole("checkbox")[1]);
    expect(screen.getByText("1 selected")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Hide selection checkboxes" }));
    expect(screen.queryAllByRole("checkbox")).toHaveLength(0);
    expect(screen.getByText("0 selected")).toBeInTheDocument();
  });

  it("remembers the checkbox column across mounts via saved preferences", () => {
    localStorage.setItem("txn-default-show-checkboxes", JSON.stringify(true));
    renderWithRouter(<TransactionTable transactions={[makeTx(), makeTx()]} />);
    expect(screen.getAllByRole("checkbox")).toHaveLength(3);
    expect(screen.getByRole("button", { name: "Hide selection checkboxes" })).toBeInTheDocument();
  });

  it("selects a contiguous range with shift-click", () => {
    renderWithRouter(
      <TransactionTable transactions={[makeTx(), makeTx(), makeTx(), makeTx()]} />,
    );
    revealCheckboxes();
    const rowBoxes = screen.getAllByRole("checkbox").slice(1);
    fireEvent.click(rowBoxes[0]);
    fireEvent.click(rowBoxes[3], { shiftKey: true });
    expect(screen.getByText("4 selected")).toBeInTheDocument();
  });

  it("bulk-assigns a category through one bulk_update request", async () => {
    renderWithRouter(
      <TransactionTable
        transactions={[makeTx({ id: "a1" }), makeTx({ id: "a2" })]}
      />,
    );
    revealCheckboxes();
    const [selectAll] = screen.getAllByRole("checkbox");
    fireEvent.click(selectAll);
    fireEvent.click(screen.getByRole("button", { name: "Assign category" }));
    fireEvent.click(await screen.findByRole("button", { name: "Food" }));

    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith(
        "/cash_transactions/bulk_update",
        { ids: [ "a1", "a2" ], category_id: "c1" },
      );
    });
    expect(mockedApi.patch).not.toHaveBeenCalled();
  });
});

describe("TransactionTable — detail drawer", () => {
  it("opens the drawer when a row is clicked", async () => {
    renderWithRouter(
      <TransactionTable transactions={[makeTx({ merchant_name: "Delta", amount: -321 })]} />,
    );
    fireEvent.click(screen.getByText("Delta"));
    expect(await screen.findByText("Transaction")).toBeInTheDocument();
    // amount appears in both the row and the drawer once open
    expect(screen.getAllByText("-$321.00").length).toBeGreaterThanOrEqual(2);
  });

  it("adds an existing tag from the tag picker", async () => {
    renderWithRouter(
      <TransactionTable transactions={[makeTx({ id: "tag-tx", merchant_name: "Delta" })]} />,
    );
    fireEvent.click(screen.getByText("Delta"));
    fireEvent.click(await screen.findByRole("button", { name: /Add tag/ }));
    fireEvent.click(await screen.findByRole("button", { name: "travel" }));
    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith("/cash_transactions/tag-tx/add_tag", { tag_id: "tg1" });
    });
  });

  it("creates a brand-new tag and attaches it", async () => {
    mockedApi.post
      .mockResolvedValueOnce({ id: "tg-new", name: "opera" }) // POST /tags
      .mockResolvedValueOnce({});                             // POST add_tag
    renderWithRouter(
      <TransactionTable transactions={[makeTx({ id: "tag-tx2", merchant_name: "Delta" })]} />,
    );
    fireEvent.click(screen.getByText("Delta"));
    fireEvent.click(await screen.findByRole("button", { name: /Add tag/ }));
    fireEvent.change(screen.getByPlaceholderText("Search or create tag…"), {
      target: { value: "opera" },
    });
    fireEvent.click(screen.getByRole("button", { name: 'Create "opera"' }));
    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith("/tags", { name: "opera" });
      expect(mockedApi.post).toHaveBeenCalledWith("/cash_transactions/tag-tx2/add_tag", { tag_id: "tg-new" });
    });
  });

  it("removes a tag chip via DELETE", async () => {
    renderWithRouter(
      <TransactionTable
        transactions={[
          makeTx({ id: "tag-tx3", merchant_name: "Delta", tags: [{ id: "tg9", name: "old-tag" }] }),
        ]}
      />,
    );
    fireEvent.click(screen.getByText("Delta"));
    // Two "old-tag" renderings: row chip + drawer chip. The drawer chip contains the ✕ button.
    const drawerChips = await screen.findAllByText("old-tag");
    const chipWithRemove = drawerChips
      .map((el) => el.closest("span"))
      .find((el) => el?.querySelector("button"))!;
    fireEvent.click(within(chipWithRemove as HTMLElement).getByRole("button"));
    await waitFor(() => {
      expect(mockedApi.delete).toHaveBeenCalledWith("/cash_transactions/tag-tx3/remove_tag?tag_id=tg9");
    });
  });

  it("links a transfer partner through the link-transfer modal", async () => {
    renderWithRouter(
      <TransactionTable
        transactions={[makeTx({ id: "tr-tx", merchant_name: "Delta", amount: -12.5 })]}
      />,
    );
    fireEvent.click(screen.getByText("Delta"));
    fireEvent.click(await screen.findByRole("button", { name: /Link as transfer/ }));
    // Select the matching counterpart, then submit from the modal footer.
    fireEvent.click(await screen.findByRole("radio", { name: /TRANSFER IN/ }));
    fireEvent.click(screen.getByRole("button", { name: /Link transfer/ }));
    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith("/transfers", {
        from_transaction_id: "tr-tx",
        from_transaction_type: "CashTransaction",
        to_transaction_id: "cand1",
        to_transaction_type: "CashTransaction",
        amount: 12.5,
        auto_confirm: true,
      });
    });
  });

  it("saves an edited note on blur via PATCH", async () => {
    renderWithRouter(
      <TransactionTable transactions={[makeTx({ id: "memo-tx", merchant_name: "Delta" })]} />,
    );
    fireEvent.click(screen.getByText("Delta"));
    const note = await screen.findByPlaceholderText("Add a note…");
    fireEvent.change(note, { target: { value: "expense this" } });
    fireEvent.blur(note);
    await waitFor(() => {
      expect(mockedApi.patch).toHaveBeenCalledWith("/cash_transactions/memo-tx", { memo: "expense this" });
    });
  });
});

describe("TransactionTable — saved views", () => {
  it("creates a saved view with the current filter state", async () => {
    renderWithRouter(<TransactionTable transactions={[makeTx()]} />);
    fireEvent.click(screen.getByTitle("Saved views"));
    fireEvent.change(screen.getByPlaceholderText("View name…"), {
      target: { value: "Everything" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith("/saved_views", {
        name: "Everything",
        conditions: [],
        match_all: true,
        group_by: "none",
        primary_sort: { field: "date", dir: "desc" },
        secondary_sort: null,
      });
    });
  });
});

describe("TransactionTable — pagination", () => {
  it("pages through results with the pager controls", () => {
    localStorage.setItem("txn-default-page-size", JSON.stringify(25));
    const txns = Array.from({ length: 30 }, (_, i) =>
      makeTx({ transaction_date: `2026-01-${String((i % 28) + 1).padStart(2, "0")}` }),
    );
    const { container } = renderWithRouter(<TransactionTable transactions={txns} />);

    expect(screen.getByText("1–25 of 30")).toBeInTheDocument();
    expect(screen.getByText("1 / 2")).toBeInTheDocument();

    const pager = screen.getByText("1 / 2").parentElement!;
    const [prevBtn, nextBtn] = Array.from(pager.querySelectorAll("button"));
    expect(prevBtn).toBeDisabled();

    fireEvent.click(nextBtn);
    expect(screen.getByText("26–30 of 30")).toBeInTheDocument();
    expect(screen.getByText("2 / 2")).toBeInTheDocument();
    expect(rowTexts(container)).toHaveLength(5);
  });
});

// ── Gaps closed by the frontend/API interaction audit ────────────────────────

describe("TransactionTable — saved view deletion", () => {
  it("deletes a saved view via DELETE /saved_views/:id", async () => {
    mockedApi.get.mockImplementation(async (path: string) => {
      if (path === "/saved_views") {
        return [ { id: "sv1", name: "Groceries", conditions: [], match_all: true,
                   group_by: null, primary_sort: null, secondary_sort: null } ] as never;
      }
      return [] as never;
    });

    renderWithRouter(<TransactionTable transactions={[makeTx()]} />);
    fireEvent.click(screen.getByTitle("Saved views"));

    expect(await screen.findByText("Groceries")).toBeInTheDocument();
    fireEvent.click(screen.getByLabelText(/^Delete view /));

    await waitFor(() => {
      expect(mockedApi.delete).toHaveBeenCalledWith("/saved_views/sv1");
    });
  });
});

describe("TransactionDrawer — linked transfer spending toggle", () => {
  const TRANSFER = {
    id: "tr1",
    from_transaction_id: "spend-tx",
    from_transaction_type: "CashTransaction",
    to_transaction_id: "other-tx",
    to_transaction_type: "CashTransaction",
    amount: 250,
    kind: "transfer",
    include_in_spend: false,
    confirmation_source: "user",
    confirmed_at: "2026-01-16T00:00:00Z",
    counterparty_account_name: "Schwab",
    from_description: "TRANSFER OUT",
    to_description: "TRANSFER IN",
  };

  function stubTransfer(overrides: Record<string, unknown> = {}) {
    // Transfers are hidden from the table by default; the drawer under test is
    // only reachable when they're shown.
    localStorage.setItem("txn-default-show-transfers", JSON.stringify(true));
    mockedApi.get.mockImplementation(async (path: string) => {
      if (path.startsWith("/transfers/for_transaction")) {
        return { ...TRANSFER, ...overrides } as never;
      }
      return [] as never;
    });
  }

  it("counts an excluded transfer as spending via PATCH /transfers/:id", async () => {
    stubTransfer();
    renderWithRouter(
      <TransactionTable
        transactions={[ makeTx({ id: "spend-tx", description: "TRANSFER OUT", amount: -250, transfer_id: "tr1" }) ]}
      />,
    );
    fireEvent.click(screen.getByText("TRANSFER OUT"));

    fireEvent.click(await screen.findByRole("button", { name: "Count as spending" }));

    await waitFor(() => {
      expect(mockedApi.patch).toHaveBeenCalledWith("/transfers/tr1", { include_in_spend: true });
    });
  });

  it("excludes an included transfer from spending via PATCH /transfers/:id", async () => {
    stubTransfer({ include_in_spend: true });
    renderWithRouter(
      <TransactionTable
        transactions={[ makeTx({ id: "spend-tx", description: "TRANSFER OUT", amount: -250, transfer_id: "tr1" }) ]}
      />,
    );
    fireEvent.click(screen.getByText("TRANSFER OUT"));

    expect(await screen.findByText("Counted in spending")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Exclude from spending" }));

    await waitFor(() => {
      expect(mockedApi.patch).toHaveBeenCalledWith("/transfers/tr1", { include_in_spend: false });
    });
  });

  it("offers no spending toggle on the receiving (positive) side", async () => {
    stubTransfer();
    renderWithRouter(
      <TransactionTable
        transactions={[ makeTx({ id: "spend-tx", description: "TRANSFER IN", amount: 250, transfer_id: "tr1" }) ]}
      />,
    );
    fireEvent.click(screen.getByText("TRANSFER IN"));

    expect(await screen.findByText("Not counted in income")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /spending/i })).toBeNull();
  });
});
