import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithClient } from "@/test/queryClient";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { LinkTransferModal } from "./LinkTransferModal";
import type { Account, CashTransaction } from "@/api/types";

const apiMock = vi.mocked(api);

const TX: CashTransaction = {
  id: "tx1",
  source: "plaid_sync",
  transaction_date: "2026-06-15",
  transfer_id: null,
  post_date: null,
  description: "VANGUARD BUY",
  amount: -2000,
  transaction_type: "DEBIT",
  category_id: null,
  category_name: null,
  merchant_id: null,
  merchant_name: null,
  account_id: "a0",
  account_name: "Checking",
  balance: null,
  memo: null,
  loan_id: null,
  loan_name: null,
  tags: [],
  created_at: "2026-06-15T00:00:00Z",
};

const ACCOUNTS = [
  { id: "a0", name: "Checking", kind: "standard", broker_name: "Chase", hidden: false, account_type: "Depository" },
  { id: "a1", name: "Brokerage", kind: "standard", broker_name: "Fidelity", hidden: false, account_type: "Investment" },
  { id: "a2", name: "Old Schwab", kind: "external", broker_name: null, hidden: false, account_type: null },
  { id: "a3", name: "Chase Sapphire", kind: "standard", broker_name: "Chase", hidden: false, account_type: "Credit Card" },
] as unknown as Account[];

const CANDIDATES = [
  { id: "cand1", description: "TRANSFER IN", account_name: "Brokerage", transaction_date: "2026-06-16", amount: 2000 },
];

function stubGets({ candidates = CANDIDATES }: { candidates?: typeof CANDIDATES } = {}) {
  apiMock.get.mockImplementation((path: string) => {
    if (path.startsWith("/cash_transactions/transfer_search")) return Promise.resolve(candidates);
    if (path === "/accounts") return Promise.resolve(ACCOUNTS);
    return Promise.resolve([]);
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  apiMock.post.mockResolvedValue({});
});

describe("LinkTransferModal", () => {
  it("disables submit until something is selected", async () => {
    stubGets();
    renderWithClient(<LinkTransferModal tx={TX} onClose={() => {}} />);
    expect(await screen.findByRole("radio", { name: /TRANSFER IN/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Link transfer/ })).toBeDisabled();
  });

  it("creates a pair when a matching transaction is selected", async () => {
    stubGets();
    const onClose = vi.fn();
    renderWithClient(<LinkTransferModal tx={TX} onClose={onClose} />);

    await userEvent.click(await screen.findByRole("radio", { name: /TRANSFER IN/ }));
    await userEvent.click(screen.getByRole("button", { name: /Link transfer/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers", {
        from_transaction_id: "tx1",
        from_transaction_type: "CashTransaction",
        to_transaction_id: "cand1",
        to_transaction_type: "CashTransaction",
        amount: 2000,
        auto_confirm: true,
      });
    });
    expect(onClose).toHaveBeenCalled();
  });

  it("creates a one-sided transfer when an account is chosen", async () => {
    stubGets({ candidates: [] });
    renderWithClient(<LinkTransferModal tx={TX} onClose={() => {}} />);

    expect(await screen.findByText(/Nothing moving the other way within two weeks/)).toBeInTheDocument();
    await userEvent.click(screen.getByLabelText("Account"));
    await userEvent.click(await screen.findByText("Brokerage"));
    await userEvent.click(screen.getByRole("button", { name: /Link transfer/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers", {
        from_transaction_id: "tx1",
        from_transaction_type: "CashTransaction",
        counterparty_account_id: "a1",
        amount: 2000,
        auto_confirm: true,
      });
    });
  });

  it("puts an inflow on the to-side of a one-sided transfer", async () => {
    stubGets({ candidates: [] });
    renderWithClient(
      <LinkTransferModal tx={{ ...TX, amount: 2000 }} onClose={() => {}} />,
    );

    expect(await screen.findByText("Where did this money come from?")).toBeInTheDocument();
    await userEvent.click(screen.getByLabelText("Account"));
    await userEvent.click(await screen.findByText("Brokerage"));
    await userEvent.click(screen.getByRole("button", { name: /Link transfer/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers", {
        to_transaction_id: "tx1",
        to_transaction_type: "CashTransaction",
        counterparty_account_id: "a1",
        amount: 2000,
        auto_confirm: true,
      });
    });
  });

  it("creates an external account inline and links to it", async () => {
    stubGets({ candidates: [] });
    apiMock.post.mockImplementation((path: string) => {
      if (path === "/accounts") {
        return Promise.resolve({ id: "ext-new", name: "Schwab", kind: "external", hidden: false });
      }
      return Promise.resolve({});
    });
    renderWithClient(<LinkTransferModal tx={TX} onClose={() => {}} />);

    await userEvent.type(await screen.findByLabelText("Account"), "Schwab");
    await userEvent.click(await screen.findByText(/Create external account/));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/accounts", { name: "Schwab", kind: "external" });
    });
    await userEvent.click(screen.getByRole("button", { name: /Link transfer/ }));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers", expect.objectContaining({
        counterparty_account_id: "ext-new",
      }));
    });
  });

  it("hands off to automation when 'always do this' is checked", async () => {
    stubGets({ candidates: [] });
    const onCreateAutomation = vi.fn();
    renderWithClient(
      <LinkTransferModal tx={TX} onClose={() => {}} onCreateAutomation={onCreateAutomation} />,
    );

    await userEvent.click(await screen.findByLabelText("Account"));
    await userEvent.click(await screen.findByText("Brokerage"));
    // The automation offer appears only for the account path.
    await userEvent.click(screen.getByRole("checkbox"));
    await userEvent.click(screen.getByRole("button", { name: /Link transfer/ }));

    await waitFor(() => {
      expect(onCreateAutomation).toHaveBeenCalledWith({ id: "a1", name: "Brokerage" });
    });
  });

  it("excludes the transaction's own account from the picker", async () => {
    stubGets({ candidates: [] });
    renderWithClient(<LinkTransferModal tx={TX} onClose={() => {}} />);

    await userEvent.click(await screen.findByLabelText("Account"));
    expect(await screen.findByText("Brokerage")).toBeInTheDocument();
    expect(screen.queryByText("Checking")).toBeNull();
  });
});

describe("LinkTransferModal: credit_card_payment mode", () => {
  it("scopes the account picker to Credit Card accounts and forces kind on submit", async () => {
    stubGets({ candidates: [] });
    renderWithClient(<LinkTransferModal tx={TX} onClose={() => {}} mode="credit_card_payment" />);

    expect(await screen.findByRole("heading", { name: "Mark as credit card payment" })).toBeInTheDocument();

    await userEvent.click(screen.getByLabelText("Account"));
    expect(await screen.findByText("Chase Sapphire")).toBeInTheDocument();
    expect(screen.queryByText("Brokerage")).toBeNull();

    await userEvent.click(screen.getByText("Chase Sapphire"));
    await userEvent.click(screen.getByRole("button", { name: /Mark as payment/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers", {
        from_transaction_id: "tx1",
        from_transaction_type: "CashTransaction",
        counterparty_account_id: "a3",
        amount: 2000,
        auto_confirm: true,
        kind: "credit_card_payment",
      });
    });
  });

  it("asks for the paying account when opened from the card-side credit", async () => {
    stubGets({ candidates: [] });
    renderWithClient(
      <LinkTransferModal
        tx={{ ...TX, amount: 626.28, account_id: "a3", account_name: "Chase Sapphire" }}
        onClose={() => {}}
        mode="credit_card_payment"
      />,
    );

    expect(await screen.findByText("Which account paid off this card?")).toBeInTheDocument();

    // Picker scopes to non-card accounts on this side.
    await userEvent.click(screen.getByLabelText("Account"));
    expect(await screen.findByText("Checking")).toBeInTheDocument();
    expect(screen.queryByText("Chase Sapphire")).toBeNull();

    await userEvent.click(screen.getByText("Checking"));
    await userEvent.click(screen.getByRole("button", { name: /Mark as payment/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/transfers", {
        to_transaction_id: "tx1",
        to_transaction_type: "CashTransaction",
        counterparty_account_id: "a0",
        amount: 626.28,
        auto_confirm: true,
        kind: "credit_card_payment",
      });
    });
  });

  it("creates newly-typed paying accounts as Checking type from the card side", async () => {
    stubGets({ candidates: [] });
    apiMock.post.mockImplementation((path: string) => {
      if (path === "/accounts") {
        return Promise.resolve({ id: "chk-new", name: "BofA Checking", kind: "external", hidden: false, account_type: "Checking" });
      }
      return Promise.resolve({});
    });
    renderWithClient(
      <LinkTransferModal
        tx={{ ...TX, amount: 626.28, account_id: "a3", account_name: "Chase Sapphire" }}
        onClose={() => {}}
        mode="credit_card_payment"
      />,
    );

    await userEvent.type(await screen.findByLabelText("Account"), "BofA Checking");
    await userEvent.click(await screen.findByText(/Create external account/));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/accounts", { name: "BofA Checking", kind: "external", account_type: "Checking" });
    });
  });

  it("creates newly-typed accounts as Credit Card type", async () => {
    stubGets({ candidates: [] });
    apiMock.post.mockImplementation((path: string) => {
      if (path === "/accounts") {
        return Promise.resolve({ id: "cc-new", name: "Amex Gold", kind: "external", hidden: false, account_type: "Credit Card" });
      }
      return Promise.resolve({});
    });
    renderWithClient(<LinkTransferModal tx={TX} onClose={() => {}} mode="credit_card_payment" />);

    await userEvent.type(await screen.findByLabelText("Account"), "Amex Gold");
    await userEvent.click(await screen.findByText(/Create external account/));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/accounts", { name: "Amex Gold", kind: "external", account_type: "Credit Card" });
    });
  });
});
