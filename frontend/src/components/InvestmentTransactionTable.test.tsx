import { describe, it, expect, vi } from "vitest";
import { screen, fireEvent } from "@testing-library/react";
import { renderWithRouter } from "@/test/queryClient";

// Stub the drawer (it has its own tests) and FilterBar to keep this focused.
vi.mock("@/api/client", () => ({ api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() } }));
vi.mock("./InvestmentTransactionDrawer", () => ({
  InvestmentTransactionDrawer: ({ tx }: { tx: { id: string } }) => <div data-testid={`drawer-${tx.id}`} />,
}));

import { InvestmentTransactionTable } from "./InvestmentTransactionTable";

function makeTx(overrides: Partial<{
  id: string;
  account_name: string;
  trade_date: string;
  security_ticker: string;
  security_name: string;
  transaction_type: string;
  transaction_type_category: string;
  description: string;
  quantity: number;
  amount_usd: number;
  cost_usd: number;
}>) {
  return {
    id: overrides.id ?? "tx-1",
    account_name: overrides.account_name ?? "Brokerage",
    trade_date: overrides.trade_date ?? "2026-01-15",
    security_ticker: overrides.security_ticker ?? "AAPL",
    security_name: overrides.security_name ?? "Apple Inc.",
    transaction_type: overrides.transaction_type ?? "Bought",
    transaction_type_category: overrides.transaction_type_category ?? "Purchase",
    description: overrides.description ?? "Purchase",
    quantity: overrides.quantity ?? 10,
    price_usd: 150,
    amount_usd: overrides.amount_usd ?? 1500,
    cost_usd: overrides.cost_usd ?? 1500,
    income_usd: 0,
    gl_long_usd: 0,
    gl_short_usd: 0,
  } as never;
}

describe("InvestmentTransactionTable", () => {
  it("renders an empty-state when no transactions", () => {
    renderWithRouter(<InvestmentTransactionTable transactions={[]} />);
    expect(screen.getByText(/no.*transactions/i)).toBeInTheDocument();
  });

  it("renders ticker and amount cells for each transaction", () => {
    renderWithRouter(
      <InvestmentTransactionTable transactions={[
        makeTx({ id: "t1", security_ticker: "AAPL", amount_usd: 1500 }),
        makeTx({ id: "t2", security_ticker: "MSFT", amount_usd: 800 }),
      ]} />,
    );
    expect(screen.getByText("AAPL")).toBeInTheDocument();
    expect(screen.getByText("MSFT")).toBeInTheDocument();
    expect(screen.getByText("$1,500.00")).toBeInTheDocument();
    expect(screen.getByText("$800.00")).toBeInTheDocument();
  });

  it("groups by month by default", () => {
    renderWithRouter(
      <InvestmentTransactionTable transactions={[
        makeTx({ id: "t1", trade_date: "2026-01-15", security_ticker: "AAPL" }),
        makeTx({ id: "t2", trade_date: "2026-02-15", security_ticker: "MSFT" }),
      ]} />,
    );
    expect(screen.getByText(/January 2026/)).toBeInTheDocument();
    expect(screen.getByText(/February 2026/)).toBeInTheDocument();
  });

  it("opens the drawer when a transaction row is clicked", () => {
    renderWithRouter(
      <InvestmentTransactionTable transactions={[ makeTx({ id: "t1", security_ticker: "TSLA" }) ]} />,
    );
    fireEvent.click(screen.getByText("TSLA"));
    expect(screen.getByTestId("drawer-t1")).toBeInTheDocument();
  });
});
