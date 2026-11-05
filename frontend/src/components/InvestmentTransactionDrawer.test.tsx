import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, fireEvent, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithClient } from "@/test/queryClient";
import { InvestmentTransactionDrawer } from "./InvestmentTransactionDrawer";
import type { InvestmentTransaction } from "@/api/types";

vi.mock("@/api/client", () => ({ api: { post: vi.fn(), get: vi.fn(), patch: vi.fn(), delete: vi.fn() } }));
import { api } from "@/api/client";
const apiMock = vi.mocked(api);

const baseTx: InvestmentTransaction = {
  id: "tx-1",
  account_name: "Brokerage",
  trade_date: "2026-01-15T12:00:00",
  description: "AAPL purchase",
  transaction_type: "Bought",
  transaction_type_category: "Purchase",
  security_id: "sec-1",
  security_ticker: "AAPL",
  security_name: "Apple Inc.",
  quantity: 10,
  price_usd: 150,
  amount_usd: 1500,
  cost_usd: 1500,
  income_usd: 0,
  gl_short_usd: 0,
  gl_long_usd: 0,
} as InvestmentTransaction;

beforeEach(() => {
  apiMock.post.mockReset();
  apiMock.post.mockResolvedValue({ status: "updated" } as never);
});

describe("InvestmentTransactionDrawer", () => {
  it("renders ticker, transaction type, and the headline amount", () => {
    renderWithClient(<InvestmentTransactionDrawer tx={baseTx} onClose={() => {}} />);
    expect(screen.getByText(/AAPL.*Bought/)).toBeInTheDocument();
    // Amount/cost both equal $1,500, so the value can appear in multiple slots
    expect(screen.getAllByText("$1,500.00").length).toBeGreaterThanOrEqual(1);
  });

  it("renders trade date, quantity, and price fields", () => {
    renderWithClient(<InvestmentTransactionDrawer tx={baseTx} onClose={() => {}} />);
    expect(screen.getByText("Trade date")).toBeInTheDocument();
    expect(screen.getByText("Jan 15, 2026")).toBeInTheDocument();
    expect(screen.getByText("Quantity")).toBeInTheDocument();
    expect(screen.getByText("10")).toBeInTheDocument();
    expect(screen.getByText("Price")).toBeInTheDocument();
    expect(screen.getByText("$150.00")).toBeInTheDocument();
  });

  it("shows the Realized G/L row with color when gl is non-zero", () => {
    renderWithClient(
      <InvestmentTransactionDrawer
        tx={{ ...baseTx, transaction_type_category: "Sale", gl_short_usd: 50, gl_long_usd: 150 } as InvestmentTransaction}
        onClose={() => {}}
      />
    );
    expect(screen.getByText("Realized G/L")).toBeInTheDocument();
    expect(screen.getByText("$200.00")).toHaveClass("text-positive");
  });

  it("calls onClose when the close button is clicked", async () => {
    const onClose = vi.fn();
    renderWithClient(<InvestmentTransactionDrawer tx={baseTx} onClose={onClose} />);
    await userEvent.setup().click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalled();
  });

  it("calls onClose when Escape is pressed", async () => {
    const onClose = vi.fn();
    renderWithClient(<InvestmentTransactionDrawer tx={baseTx} onClose={onClose} />);
    fireEvent.keyDown(window, { key: "Escape" });
    expect(onClose).toHaveBeenCalled();
  });

  it("shows the reprocess button for Purchase/Sale txns and fires the mutation", async () => {
    const onReprocessed = vi.fn();
    renderWithClient(
      <InvestmentTransactionDrawer tx={baseTx} onClose={() => {}} onReprocessed={onReprocessed} />,
    );
    const btn = screen.getByRole("button", { name: /update holdings/i });
    await userEvent.setup().click(btn);
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/investment_transactions/tx-1/reprocess");
      expect(onReprocessed).toHaveBeenCalled();
    });
    await waitFor(() => expect(screen.getByText(/Holdings updated/i)).toBeInTheDocument());
  });

  it("hides the reprocess button for income txns (non-Purchase/Sale)", () => {
    renderWithClient(
      <InvestmentTransactionDrawer
        tx={{ ...baseTx, transaction_type_category: "Dividend", transaction_type: "Dividend", income_usd: 42 } as InvestmentTransaction}
        onClose={() => {}}
      />
    );
    expect(screen.queryByRole("button", { name: /update holdings/i })).toBeNull();
  });

  it("inline mode skips the modal backdrop", () => {
    const { container } = renderWithClient(
      <InvestmentTransactionDrawer tx={baseTx} onClose={() => {}} inline />,
    );
    expect(container.querySelectorAll(".bg-black\\/40").length).toBe(0);
  });
});
