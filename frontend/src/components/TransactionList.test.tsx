import { describe, it, expect, vi } from "vitest";
import { screen, fireEvent } from "@testing-library/react";
import { renderWithRouter } from "@/test/queryClient";

// TransactionTable is huge + pulls in FilterBar. We're testing the mobile-list
// path in TransactionList here, so stub it out.
vi.mock("./TransactionTable", () => ({
  TransactionTable: () => <div data-testid="transaction-table" />,
  amountColor: () => "",
}));
vi.mock("./TransactionDrawer", () => ({
  TransactionDrawer: ({ tx }: { tx: { id: string } }) => <div data-testid={`drawer-${tx.id}`} />,
}));

vi.mock("@/api/client", () => ({ api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() } }));

import { TransactionList, ResponsiveTransactionView } from "./TransactionList";

function makeTx(overrides: Partial<{ id: string; description: string; transaction_date: string; amount: number; merchant_name: string | null; category_name: string | null; account_name: string; transfer_id: string | null }>) {
  return {
    id: overrides.id ?? "tx-1",
    transaction_date: overrides.transaction_date ?? "2026-01-15",
    description: overrides.description ?? "Generic txn",
    amount: overrides.amount ?? -10,
    source: "bank",
    transaction_type: "Sale",
    merchant_id: null,
    merchant_name: overrides.merchant_name ?? null,
    category_id: null,
    category_name: overrides.category_name ?? null,
    account_id: "a1",
    account_name: overrides.account_name ?? "Checking",
    transfer_id: overrides.transfer_id ?? null,
  } as never;
}

describe("TransactionList", () => {
  it("shows an empty-state message when there are no transactions", () => {
    renderWithRouter(<TransactionList transactions={[]} />);
    expect(screen.getByText("No transactions yet.")).toBeInTheDocument();
  });

  it("renders one row per transaction (merchant > category > account)", () => {
    renderWithRouter(<TransactionList transactions={[
      makeTx({ id: "1", description: "STARBUCKS", merchant_name: "Starbucks" }),
      makeTx({ id: "2", description: "WALMART",   merchant_name: null, account_name: "AmexCC" }),
    ]} />);
    // Merchant is the secondary label when present
    expect(screen.getByText("Starbucks")).toBeInTheDocument();
    // Falls through to account_name when no merchant/category
    expect(screen.getByText("AmexCC")).toBeInTheDocument();
  });

  it("renders skeleton placeholders while loading", () => {
    const { container } = renderWithRouter(<TransactionList transactions={[]} isLoading />);
    // 8 skeleton placeholder rows when loading
    const placeholders = container.querySelectorAll(".animate-pulse");
    expect(placeholders.length).toBeGreaterThanOrEqual(8);
    expect(screen.queryByText("No transactions yet.")).toBeNull();
  });

  it("opens the drawer when a row is clicked", () => {
    renderWithRouter(<TransactionList transactions={[
      makeTx({ id: "1", merchant_name: "Pizza Place" }),
    ]} />);
    fireEvent.click(screen.getByText("Pizza Place"));
    expect(screen.getByTestId("drawer-1")).toBeInTheDocument();
  });

  it("only shows pagination when there are more than PAGE_SIZE rows", () => {
    const rows = Array.from({ length: 105 }).map((_, i) =>
      makeTx({ id: `t-${i}`, description: `txn ${i}`, transaction_date: "2026-01-15" }),
    );
    renderWithRouter(<TransactionList transactions={rows} />);
    expect(screen.getByText("1–100 of 105")).toBeInTheDocument();
    expect(screen.getByText("1 / 2")).toBeInTheDocument();
  });

  it("honors the columns prop when picking the secondary label", () => {
    renderWithRouter(
      <TransactionList
        columns={[ "category", "account" ]}
        transactions={[ makeTx({
          id: "1", description: "DESC",
          merchant_name: "Should Hide",
          category_name: "Groceries",
          account_name: "Checking",
        }) ]}
      />,
    );
    // With merchant column hidden, category is the secondary label
    expect(screen.getByText("Groceries")).toBeInTheDocument();
    expect(screen.queryByText("Should Hide")).toBeNull();
  });

  it("hides transfer legs like the desktop table does", () => {
    renderWithRouter(<TransactionList transactions={[
      makeTx({ id: "1", merchant_name: "Coffee" }),
      makeTx({ id: "2", merchant_name: "Savings Move", transfer_id: "tr-1" }),
    ]} />);
    expect(screen.getByText("Coffee")).toBeInTheDocument();
    expect(screen.queryByText("Savings Move")).toBeNull();
  });
});

describe("ResponsiveTransactionView on a narrow screen", () => {
  it("applies drill-down initialFilters in the mobile list", () => {
    const originalWidth = window.innerWidth;
    Object.defineProperty(window, "innerWidth", { configurable: true, value: 500 });
    try {
      renderWithRouter(
        <ResponsiveTransactionView
          initialFilters={[{ _key: 1, field: "transaction_date", operator: "month", value: "2026-02" }]}
          transactions={[
            makeTx({ id: "1", merchant_name: "January Rent", transaction_date: "2026-01-15" }),
            makeTx({ id: "2", merchant_name: "February Rent", transaction_date: "2026-02-15" }),
          ]}
        />,
      );
      expect(screen.queryByTestId("transaction-table")).toBeNull();
      expect(screen.getByText("February Rent")).toBeInTheDocument();
      expect(screen.queryByText("January Rent")).toBeNull();
    } finally {
      Object.defineProperty(window, "innerWidth", { configurable: true, value: originalWidth });
    }
  });
});
