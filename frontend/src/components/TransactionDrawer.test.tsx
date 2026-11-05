import { describe, it, expect, beforeEach, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter, useLocation } from "react-router-dom";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { TransactionDrawer } from "./TransactionDrawer";
import type { CashTransaction } from "@/api/types";

const apiMock = vi.mocked(api);

const TX: CashTransaction = {
  id: "tx1",
  source: "csv_import",
  transaction_date: "2026-06-15",
  transfer_id: "tr1", // already a transfer — silences the pending-transfer lookup
  post_date: null,
  description: "WHOLE FOODS MARKET",
  amount: -42.1,
  transaction_type: "DEBIT",
  category_id: null,
  category_name: null,
  merchant_id: "m1",
  merchant_name: "Whole Foods",
  account_id: null,
  account_name: null,
  balance: null,
  memo: null,
  loan_id: null,
  loan_name: null,
  tags: [],
  created_at: "2026-06-15T00:00:00Z",
};

function LocationProbe() {
  const loc = useLocation();
  return <div data-testid="location">{loc.pathname}</div>;
}

function renderDrawer(tx: CashTransaction = TX, { onClose = vi.fn() } = {}) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <TransactionDrawer tx={tx} onClose={onClose} />
        <LocationProbe />
      </MemoryRouter>
    </QueryClientProvider>
  );
}

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  // The quick-automation modal's live preview polls the filter endpoint.
  apiMock.post.mockResolvedValue({ transactions: [], total: 0 } as never);
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/merchants") return [{ id: "m1", name: "Whole Foods", category_id: null, category_name: null, notes: null, transaction_count: 3, excluded: false }] as never;
    if (path === "/categories") return [] as never;
    if (path === "/tags") return [] as never;
    if (path.startsWith("/transfers/for_transaction")) return null as never;
    if (path.endsWith("/similar")) return { transactions: [], total: 0, total_amount: 0 } as never;
    if (path.startsWith("/cash_transactions/transfer_search")) return [] as never;
    if (path === "/accounts") return [] as never;
    return [] as never;
  });
});

describe("TransactionDrawer: quick automation", () => {
  it("opens the QuickAutomationModal pre-filled from the transaction", async () => {
    renderDrawer();

    await userEvent.click(screen.getByRole("button", { name: "Create automation" }));

    expect(await screen.findByRole("heading", { name: "Create automation" })).toBeInTheDocument();
    expect(screen.getByLabelText("Name")).toHaveValue("Auto: WHOLE FOODS MARKET");
    expect(screen.getByLabelText("Description matches")).toHaveValue("WHOLE FOODS MARKET");
    expect(screen.getByLabelText("Source equals")).toHaveValue("csv_import");
  });

  it("closes the modal via its close button", async () => {
    renderDrawer();

    await userEvent.click(screen.getByRole("button", { name: "Create automation" }));
    expect(await screen.findByRole("heading", { name: "Create automation" })).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.queryByRole("heading", { name: "Create automation" })).not.toBeInTheDocument();
  });
});

describe("TransactionDrawer: mark as credit card payment", () => {
  const unlinkedOutflow: CashTransaction = { ...TX, transfer_id: null, amount: -250 };

  it("offers a dedicated action for an unlinked outflow, opening the modal in payment mode", async () => {
    renderDrawer(unlinkedOutflow);

    const button = await screen.findByRole("button", { name: "Mark as credit card payment" });
    await userEvent.click(button);

    expect(await screen.findByRole("heading", { name: "Mark as credit card payment" })).toBeInTheDocument();
    expect(screen.getByText("Which credit card did this pay off?")).toBeInTheDocument();
  });

  it("does not offer the action for an unlinked inflow", async () => {
    renderDrawer({ ...TX, transfer_id: null, amount: 250 });

    expect(await screen.findByRole("button", { name: "Link as transfer" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Mark as credit card payment" })).not.toBeInTheDocument();
  });

  it("still offers the generic link-as-transfer action alongside it", async () => {
    renderDrawer(unlinkedOutflow);

    expect(await screen.findByRole("button", { name: "Mark as credit card payment" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Link as transfer" })).toBeInTheDocument();
  });
});

describe("TransactionDrawer: card-side payment settlement state", () => {
  const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString().slice(0, 10);

  const paymentCredit: CashTransaction = {
    ...TX,
    transfer_id: null,
    amount: 626.28,
    transaction_type: "Payment",
    description: "Automatic Payment - Thank You",
    transaction_date: daysAgo(1),
  };

  it("shows an awaiting-settlement card for a recent unlinked payment credit", async () => {
    renderDrawer(paymentCredit);

    expect(await screen.findByText(/Awaiting settlement/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Link payment source" })).toBeInTheDocument();
  });

  it("explains an unmatched payment once the match window has passed", async () => {
    renderDrawer({ ...paymentCredit, transaction_date: daysAgo(30) });

    expect(await screen.findByText(/No matching withdrawal found/)).toBeInTheDocument();
    expect(screen.queryByText(/Awaiting settlement/)).not.toBeInTheDocument();
  });

  it("opens the payment-mode link modal asking for the paying account", async () => {
    renderDrawer(paymentCredit);

    await userEvent.click(await screen.findByRole("button", { name: "Link payment source" }));

    expect(await screen.findByRole("heading", { name: "Mark as credit card payment" })).toBeInTheDocument();
    expect(screen.getByText("Which account paid off this card?")).toBeInTheDocument();
  });

  it("shows no settlement card for a linked payment credit", async () => {
    renderDrawer({ ...paymentCredit, transfer_id: "tr1" });

    expect(await screen.findByText("Automatic Payment - Thank You")).toBeInTheDocument();
    expect(screen.queryByText(/Awaiting settlement/)).not.toBeInTheDocument();
    expect(screen.queryByText(/No matching withdrawal found/)).not.toBeInTheDocument();
  });

  it("shows no settlement card for an ordinary credit", async () => {
    renderDrawer({ ...TX, transfer_id: null, amount: 250 });

    expect(await screen.findByRole("button", { name: "Link as transfer" })).toBeInTheDocument();
    expect(screen.queryByText(/Awaiting settlement/)).not.toBeInTheDocument();
  });
});

describe("TransactionDrawer: description web search", () => {
  it("links the description to the configured search engine", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/preferences") return { data: { transactions: { search_engine: "kagi" } } } as never;
      if (path === "/merchants") return [] as never;
      return [] as never;
    });

    renderDrawer();

    // The engine arrives with the preferences query, so the href starts on the
    // default and switches once it lands.
    const link = await screen.findByRole("link", { name: /WHOLE FOODS MARKET/ });
    await waitFor(() =>
      expect(link).toHaveAttribute("href", "https://kagi.com/search?q=WHOLE%20FOODS%20MARKET"));
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    expect(link).toHaveAttribute("title", 'Search Kagi for "WHOLE FOODS MARKET"');
  });

  it("falls back to Google when no engine has been picked", async () => {
    renderDrawer();

    const link = await screen.findByRole("link", { name: /WHOLE FOODS MARKET/ });
    expect(link).toHaveAttribute("href", "https://www.google.com/search?q=WHOLE%20FOODS%20MARKET");
  });

  it("leaves a blank description unlinked", async () => {
    renderDrawer({ ...TX, description: "   " });

    expect(await screen.findByText("Description")).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /Search/ })).not.toBeInTheDocument();
  });
});

describe("TransactionDrawer: similar transactions", () => {
  const SIMILAR = {
    transactions: [
      { id: "s1", transaction_date: "2026-06-10", description: "WHOLE FOODS MARKET",
        amount: -38.2, account_name: "Chase Sapphire", match: "exact" },
      { id: "s2", transaction_date: "2026-05-11", description: "WHOLE FOODS MKT 1042",
        amount: -51.75, account_name: "Chase Sapphire", match: "similar" },
    ],
    total: 9,
    total_amount: -402.5,
  };

  function stubSimilar(payload: unknown) {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === `/cash_transactions/${TX.id}/similar`) return payload as never;
      if (path === "/merchants") return [] as never;
      return [] as never;
    });
  }

  it("lists the matches with the full count and running total", async () => {
    stubSimilar(SIMILAR);
    renderDrawer();

    expect(await screen.findByText("Similar transactions")).toBeInTheDocument();
    expect(screen.getByText("9 · -$402.50")).toBeInTheDocument();
    expect(screen.getByText("-$38.20")).toBeInTheDocument();
    expect(screen.getByText("-$51.75")).toBeInTheDocument();
    // The near-match shows how its descriptor differs; the exact one doesn't
    // repeat what the pane already says above.
    expect(screen.getByText("~ WHOLE FOODS MKT 1042")).toBeInTheDocument();
    expect(screen.queryByText("~ WHOLE FOODS MARKET")).not.toBeInTheDocument();
    // 9 matches, 2 rows returned.
    expect(screen.getByText("+ 7 more")).toBeInTheDocument();
  });

  it("opens a match's full detail page, closing the pane first", async () => {
    stubSimilar(SIMILAR);
    const onClose = vi.fn();
    renderDrawer(TX, { onClose });

    await userEvent.click(await screen.findByTitle("WHOLE FOODS MKT 1042"));

    expect(onClose).toHaveBeenCalled();
    expect(screen.getByTestId("location")).toHaveTextContent("/transactions/s2");
  });

  it("says so when the description stands alone", async () => {
    stubSimilar({ transactions: [], total: 0, total_amount: 0 });
    renderDrawer();

    expect(await screen.findByText("No others with this description.")).toBeInTheDocument();
  });
});
