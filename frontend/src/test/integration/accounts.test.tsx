import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, fireEvent } from "@testing-library/react";
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
import { formatDate } from "@/lib/utils";
import type { Account } from "@/api/types";

const apiMock = vi.mocked(api);

/** Header actions now live in the "Page actions" pencil dropdown; menu items
 *  render in a portal on document.body. */
async function clickPageAction(name: RegExp | string) {
  await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
  fireEvent.click(await screen.findByRole("menuitem", { name }));
}

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const ACCOUNTS: Account[] = [
  {
    id: "a1", name: "Everyday Checking", account_number: "111122223333",
    account_type: "checking", balance: 5200.5, balance_currency: "USD",
    balance_usd: 5200.5, broker_id: "b1", broker_name: "Chase",
    plaid_item_id: null, cash_transaction_count: 2, investment_transaction_count: 0,
    portfolio_value: 0, latest_transaction_date: "2026-06-20",
    linked_loan_id: null, hidden: false,
  },
  {
    id: "a2", name: "Sapphire Card", account_number: "9876",
    account_type: "credit card", balance: null, balance_currency: "USD",
    balance_usd: null, broker_id: "b1", broker_name: "Chase",
    plaid_item_id: null, cash_transaction_count: 0, investment_transaction_count: 0,
    portfolio_value: 0, latest_transaction_date: null,
    linked_loan_id: null, hidden: false,
  },
  {
    id: "a3", name: "Taxable Brokerage", account_number: "5555",
    account_type: "brokerage", balance: null, balance_currency: "USD",
    balance_usd: null, broker_id: "b2", broker_name: "Schwab",
    plaid_item_id: null, cash_transaction_count: 0, investment_transaction_count: 0,
    portfolio_value: 100000, latest_transaction_date: "2026-06-30",
    linked_loan_id: null, hidden: false,
  },
  {
    id: "a4", name: "Secret Savings", account_number: "",
    account_type: "savings", balance: 900, balance_currency: "USD",
    balance_usd: 900, broker_id: "b2", broker_name: "Schwab",
    plaid_item_id: null, cash_transaction_count: 0, investment_transaction_count: 0,
    portfolio_value: 0, latest_transaction_date: null,
    linked_loan_id: null, hidden: true,
  },
];

const ACCOUNT_TXNS = [
  {
    id: "tx-1", transaction_date: "2026-06-18", description: "PAYROLL DEPOSIT",
    amount: 2500, source: "checking", transaction_type: "Credit",
    merchant_id: null, merchant_name: null, category_id: null, category_name: null,
    account_id: "a1", account_name: "Everyday Checking",
    created_at: "2026-06-18T10:00:00Z", tags: [], memo: null,
  },
  {
    id: "tx-2", transaction_date: "2026-06-20", description: "RENT PAYMENT",
    amount: -1800, source: "checking", transaction_type: "Debit",
    merchant_id: null, merchant_name: null, category_id: null, category_name: null,
    account_id: "a1", account_name: "Everyday Checking",
    created_at: "2026-06-20T10:00:00Z", tags: [], memo: null,
  },
];

const SNAPSHOTS = [
  { date: "2026-05-01", balance: 4000, balance_currency: "USD", balance_usd: 4000, source: "manual" },
  { date: "2026-06-01", balance: 4800, balance_currency: "USD", balance_usd: 4800, source: "manual" },
  { date: "2026-07-01", balance: 5200.5, balance_currency: "USD", balance_usd: 5200.5, source: "manual" },
];

const HOLDINGS = {
  as_of_date: "2026-06-30",
  positions: [
    {
      id: "p1", security_ticker: "VTI", security_name: "Vanguard Total Stock Market",
      as_of_date: "2026-06-30", quantity: 200, price: 300, market_value: 60000,
      cost_basis: 45000, unrealized_gl: 15000, unrealized_gl_pct: 33.3,
      asset_class: "equity", est_annual_income: 900, dividend_yield: 1.5,
    },
    {
      id: "p2", security_ticker: "BND", security_name: "Vanguard Total Bond Market",
      as_of_date: "2026-06-30", quantity: 500, price: 80, market_value: 40000,
      cost_basis: 41000, unrealized_gl: -1000, unrealized_gl_pct: -2.4,
      asset_class: "fixed_income", est_annual_income: 1200, dividend_yield: 3.0,
    },
  ],
};

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
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
    if (path === "/accounts") return ACCOUNTS as never;
    if (path === "/cash_transactions?account_id=a1") return ACCOUNT_TXNS as never;
    if (path.startsWith("/cash_transactions?account_id=")) return [] as never;
    if (path === "/accounts/a1/balance_snapshots") return SNAPSHOTS as never;
    if (path === "/accounts/a3/holdings") return HOLDINGS as never;
    // The Monthly Spend chart is a SpendChartCard compact, fed by the
    // account-scoped breakdown endpoint.
    if (path.startsWith("/cashflow/spend_breakdown")) {
      return { monthly_spend: { "2026-06": 1800 } } as never;
    }
    return [] as never;
  });
});

describe("Accounts: broker groups", () => {
  it("groups accounts under broker headers with compact balances", async () => {
    renderApp({ initialPath: "/accounts", initialToken: "tok" });

    expect(await screen.findByRole("button", { name: "Chase" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Schwab" })).toBeInTheDocument();

    expect(screen.getByText("Everyday Checking")).toBeInTheDocument();
    expect(screen.getByText("Sapphire Card")).toBeInTheDocument();
    expect(screen.getByText("Taxable Brokerage")).toBeInTheDocument();

    // Row balances: balance_usd for cash, portfolio_value fallback for brokerage
    expect(screen.getByText("$5.2K")).toBeInTheDocument();
    expect(screen.getByText("$100K")).toBeInTheDocument();

    // Masked account number in the row
    expect(screen.getByText("····3333")).toBeInTheDocument();
  });

  it("still lists hidden accounts for the owner (current behavior)", async () => {
    renderApp({ initialPath: "/accounts", initialToken: "tok" });
    expect(await screen.findByText("Secret Savings")).toBeInTheDocument();
  });

  it("collapses a broker group and persists it to sessionStorage", async () => {
    renderApp({ initialPath: "/accounts", initialToken: "tok" });
    await screen.findByText("Everyday Checking");

    fireEvent.click(screen.getByRole("button", { name: "Chase" }));

    expect(screen.queryByText("Everyday Checking")).not.toBeInTheDocument();
    expect(screen.queryByText("Sapphire Card")).not.toBeInTheDocument();
    // Other broker's accounts stay visible
    expect(screen.getByText("Taxable Brokerage")).toBeInTheDocument();
    expect(JSON.parse(sessionStorage.getItem("acct_collapsed_brokers")!)).toEqual(["Chase"]);

    // Expanding again restores the rows and clears the persisted entry
    fireEvent.click(screen.getByRole("button", { name: "Chase" }));
    expect(screen.getByText("Everyday Checking")).toBeInTheDocument();
    expect(JSON.parse(sessionStorage.getItem("acct_collapsed_brokers")!)).toEqual([]);
  });

  it("restores collapsed groups from sessionStorage on load", async () => {
    sessionStorage.setItem("acct_collapsed_brokers", JSON.stringify(["Schwab"]));
    renderApp({ initialPath: "/accounts", initialToken: "tok" });

    expect(await screen.findByText("Everyday Checking")).toBeInTheDocument();
    expect(screen.queryByText("Taxable Brokerage")).not.toBeInTheDocument();
    expect(screen.queryByText("Secret Savings")).not.toBeInTheDocument();
  });

  it("filters the flat list while searching", async () => {
    renderApp({ initialPath: "/accounts", initialToken: "tok" });
    const search = await screen.findByPlaceholderText("Search accounts…");
    await screen.findByText("Sapphire Card");

    fireEvent.change(search, { target: { value: "sapphire" } });
    expect(screen.getByText("Sapphire Card")).toBeInTheDocument();
    expect(screen.queryByText("Everyday Checking")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Chase" })).not.toBeInTheDocument();

    fireEvent.change(search, { target: { value: "zzz" } });
    expect(screen.getByText("No accounts match")).toBeInTheDocument();
  });
});

describe("Accounts: detail pane", () => {
  it("renders header, balance, stats, balance history and transactions", async () => {
    renderApp({ initialPath: "/accounts#id=a1", initialToken: "tok" });

    // Name appears in the sidebar and detail header
    expect(await screen.findAllByText("Everyday Checking")).toHaveLength(2);
    expect(screen.getByText("$5,200.50")).toBeInTheDocument();

    // Stat ribbon
    expect(screen.getByText("Cash Txns")).toBeInTheDocument();
    expect(screen.getByText("Investment Txns")).toBeInTheDocument();
    expect(screen.getByText("Last Activity")).toBeInTheDocument();
    // Same formatted date can appear in the transaction table too
    expect(screen.getAllByText(formatDate("2026-06-20")).length).toBeGreaterThan(0);

    // Full account number in the body
    expect(screen.getByText("111122223333")).toBeInTheDocument();

    // Balance snapshots (>1) render the history chart label
    expect(await screen.findByText("Balance History")).toBeInTheDocument();

    // Cash transactions section with rows
    expect(screen.getByText("Cash Transactions")).toBeInTheDocument();
    expect(await screen.findByText("PAYROLL DEPOSIT")).toBeInTheDocument();
    expect(screen.getByText("RENT PAYMENT")).toBeInTheDocument();

    // The Monthly Spend chart is the canonical spend card scoped to this account
    expect(screen.getByText("Monthly Spend")).toBeInTheDocument();
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(expect.stringMatching(/\/cashflow\/spend_breakdown\?.*account_id=a1/));
    });
  });

  it("shows the holdings panel for an investment account", async () => {
    renderApp({ initialPath: "/accounts#id=a3", initialToken: "tok" });

    expect(await screen.findByText("Holdings")).toBeInTheDocument();
    expect(await screen.findByText("VTI")).toBeInTheDocument();
    expect(screen.getByText("BND")).toBeInTheDocument();
    expect(screen.getByText(`as of ${formatDate("2026-06-30")}`)).toBeInTheDocument();
  });

  it("PATCHes the account from the edit form, including the hidden flag", async () => {
    apiMock.patch.mockResolvedValue(ACCOUNTS[0] as never);
    renderApp({ initialPath: "/accounts#id=a1", initialToken: "tok" });
    await screen.findAllByText("Everyday Checking");

    await clickPageAction(/Edit account/i);
    expect(await screen.findByText("Edit Account")).toBeInTheDocument();

    const nameInput = screen.getByDisplayValue("Everyday Checking");
    fireEvent.change(nameInput, { target: { value: "Primary Checking" } });
    fireEvent.click(screen.getByLabelText("Hide from household"));
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/accounts/a1", {
        name: "Primary Checking",
        account_number: "111122223333",
        account_type: "checking",
        balance: 5200.5,
        hidden: true,
        tax_treatment: "taxable",
      });
    });
  });

  it("pre-checks the hidden checkbox when editing a hidden account", async () => {
    renderApp({ initialPath: "/accounts#id=a4", initialToken: "tok" });
    await screen.findAllByText("Secret Savings");

    await clickPageAction(/Edit account/i);
    expect(await screen.findByLabelText("Hide from household")).toBeChecked();
  });

  it("PATCHes balance, currency and USD value from the inline balance editor", async () => {
    apiMock.patch.mockResolvedValue(ACCOUNTS[0] as never);
    renderApp({ initialPath: "/accounts#id=a1", initialToken: "tok" });

    fireEvent.click(await screen.findByText("$5,200.50"));

    const amount = await screen.findByPlaceholderText("Amount");
    fireEvent.change(amount, { target: { value: "6000" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      // When the currency is USD the separate USD input is hidden, so
      // balance_usd must track the newly entered balance — not the stale
      // pre-filled draft from the old balance_usd.
      expect(apiMock.patch).toHaveBeenCalledWith("/accounts/a1", {
        balance: 6000,
        balance_currency: "USD",
        balance_usd: 6000,
      });
    });
  });

  it("uses the entered USD value when a non-USD currency is set", async () => {
    apiMock.patch.mockResolvedValue(ACCOUNTS[0] as never);
    renderApp({ initialPath: "/accounts#id=a1", initialToken: "tok" });

    fireEvent.click(await screen.findByText("$5,200.50"));

    fireEvent.change(await screen.findByPlaceholderText("Amount"), { target: { value: "6000" } });
    fireEvent.change(screen.getByPlaceholderText("USD"), { target: { value: "EUR" } });
    fireEvent.change(await screen.findByPlaceholderText("USD value"), { target: { value: "6450.25" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/accounts/a1", {
        balance: 6000,
        balance_currency: "EUR",
        balance_usd: 6450.25,
      });
    });
  });

  it("derives balance_usd from the amount when no prior USD value exists", async () => {
    apiMock.patch.mockResolvedValue(ACCOUNTS[1] as never);
    renderApp({ initialPath: "/accounts#id=a2", initialToken: "tok" });

    // a2 has no balance yet, so the display shows the em-dash placeholder
    await screen.findAllByText("Sapphire Card");
    fireEvent.click(screen.getByText("—"));

    const amount = await screen.findByPlaceholderText("Amount");
    fireEvent.change(amount, { target: { value: "-250.75" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/accounts/a2", {
        balance: -250.75,
        balance_currency: "USD",
        balance_usd: -250.75,
      });
    });
  });
});
