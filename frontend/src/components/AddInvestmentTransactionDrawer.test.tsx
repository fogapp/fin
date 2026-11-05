import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, waitFor, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithClient } from "@/test/queryClient";

vi.mock("@/api/client", () => ({ api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() } }));
import { api } from "@/api/client";
import { AddInvestmentTransactionDrawer } from "./AddInvestmentTransactionDrawer";

const apiMock = vi.mocked(api);

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.get.mockResolvedValue([
    { id: "acc-1", name: "Brokerage" },
    { id: "acc-2", name: "IRA" },
  ] as never);
  apiMock.post.mockResolvedValue({ id: "tx-new" } as never);
});

describe("AddInvestmentTransactionDrawer", () => {
  function renderDrawer(overrides?: { onClose?: () => void; onCreated?: () => void }) {
    return renderWithClient(
      <AddInvestmentTransactionDrawer
        securityId="sec-1"
        securityTicker="AAPL"
        onClose={overrides?.onClose ?? (() => {})}
        onCreated={overrides?.onCreated ?? (() => {})}
      />,
    );
  }

  it("renders the header with the ticker", () => {
    renderDrawer();
    expect(screen.getByText(/Add transaction.*AAPL/)).toBeInTheDocument();
  });

  it("populates the account select from /accounts", async () => {
    renderDrawer();
    await waitFor(() => {
      expect(screen.getByRole("option", { name: "Brokerage" })).toBeInTheDocument();
      expect(screen.getByRole("option", { name: "IRA" })).toBeInTheDocument();
    });
  });

  it("shows quantity + price fields for Purchase/Sale, hides them for income types", async () => {
    renderDrawer();
    expect(screen.getByText("Quantity")).toBeInTheDocument();
    expect(screen.getByText("Price per share")).toBeInTheDocument();

    // Switch to Dividend
    const user = userEvent.setup();
    const typeSelect = screen.getAllByRole("combobox")[0];
    await user.selectOptions(typeSelect, "Dividend");
    expect(screen.queryByText("Quantity")).toBeNull();
    expect(screen.queryByText("Price per share")).toBeNull();
  });

  it("shows a validation error when submitting without an account", async () => {
    renderDrawer();
    fireEvent.submit(screen.getByRole("button", { name: /save transaction/i }).closest("form")!);
    expect(await screen.findByText(/Account is required/)).toBeInTheDocument();
    expect(apiMock.post).not.toHaveBeenCalled();
  });

  it("submits the form payload and calls onCreated on success", async () => {
    const onCreated = vi.fn();
    renderDrawer({ onCreated });

    await waitFor(() => expect(screen.getByRole("option", { name: "Brokerage" })).toBeInTheDocument());
    const user = userEvent.setup();

    await user.selectOptions(screen.getAllByRole("combobox")[1], "acc-1");

    // Set quantity + amount via fireEvent for stability with type=number
    const numberInputs = screen.getAllByPlaceholderText("0.00");
    fireEvent.change(numberInputs[0], { target: { value: "10" } });
    fireEvent.change(numberInputs[1], { target: { value: "150" } });
    fireEvent.change(numberInputs[2], { target: { value: "1500" } });

    await user.click(screen.getByRole("button", { name: /save transaction/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/investment_transactions", expect.objectContaining({
        security_id: "sec-1",
        transaction_type: "Purchase",
        account_id: "acc-1",
        quantity: "10",
        price_usd: "150",
        amount_usd: "1500",
      }));
      expect(onCreated).toHaveBeenCalled();
    });
  });

  it("displays the API error message when create fails", async () => {
    apiMock.post.mockRejectedValueOnce(new Error("Validation failed"));
    renderDrawer();

    await waitFor(() => expect(screen.getByRole("option", { name: "Brokerage" })).toBeInTheDocument());
    const user = userEvent.setup();
    await user.selectOptions(screen.getAllByRole("combobox")[1], "acc-1");

    await user.click(screen.getByRole("button", { name: /save transaction/i }));
    expect(await screen.findByText("Validation failed")).toBeInTheDocument();
  });

  it("calls onClose when the close button is clicked", async () => {
    const onClose = vi.fn();
    renderDrawer({ onClose });
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalled();
  });
});
