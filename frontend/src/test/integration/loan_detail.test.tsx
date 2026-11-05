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
import type { Loan, LoanDetail, LoanTransaction, CashTransaction, AmortizationEntry } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

// 30 scheduled payments: only the first 24 render until the table is expanded.
// Balances are unique per row ($399,900 down to $397,000 in $100 steps).
function amortizationDate(i: number): string {
  return new Date(Date.UTC(2024, 1 + i, 15)).toISOString().slice(0, 10);
}

const SCHEDULE: AmortizationEntry[] = Array.from({ length: 30 }, (_, i) => ({
  payment_number: i + 1,
  payment_date: amortizationDate(i),
  payment: 2528.27,
  principal: 362 + i,
  interest: 2166 - i,
  escrow: 0,
  balance: 400000 - (i + 1) * 100,
}));

const BASE_LOAN: Loan = {
  id: "loan-1",
  name: "Lake House Mortgage",
  lender: "Rocket Mortgage",
  loan_type: "mortgage",
  original_principal: 400000,
  interest_rate: 6.5,
  term_months: 360,
  start_date: "2024-01-15",
  monthly_payment: 2528.27,
  entered_monthly_payment: null,
  principal_and_interest_payment: 2528.27,
  escrow_property_tax: null,
  escrow_insurance: null,
  escrow_other: null,
  escrow_payment: 0,
  status: "active",
  notes: null,
  interest_only: false,
  merchant_id: null,
  merchant_name: null,
  account_id: "acct-1",
  account_name: "Mortgage Checking",
  balance_anchor_amount: null,
  balance_anchor_date: null,
  total_scheduled_interest: 510181,
  total_paid: 60678.48,
  principal_paid: 10000,
  interest_paid: 50678.48,
  escrow_paid: 0,
  property_tax_paid: 0,
  insurance_paid: 0,
  other_escrow_paid: 0,
  current_balance: 390000,
  payments_count: 24,
  created_at: "2024-01-15T00:00:00Z",
  updated_at: "2026-06-01T00:00:00Z",
};

const LOAN_DETAIL: LoanDetail = {
  ...BASE_LOAN,
  amortization_schedule: SCHEDULE,
  linked_transactions: [],
};

const LINKED_TXNS: CashTransaction[] = [
  {
    id: "ct-1", source: "bank", transaction_date: "2026-05-01", transfer_id: null,
    post_date: null, description: "ROCKET MTG PAYMENT MAY", amount: -2528.27,
    transaction_type: "Payment", category_id: null, category_name: null,
    merchant_id: null, merchant_name: null, account_id: "acct-2",
    account_name: "Chase Checking", balance: null, memo: null,
    loan_id: "loan-1", loan_name: "Lake House Mortgage", tags: [],
    created_at: "2026-05-01T10:00:00Z",
  },
  {
    id: "ct-2", source: "bank", transaction_date: "2026-04-01", transfer_id: null,
    post_date: null, description: "ROCKET MTG PAYMENT APR", amount: -2528.27,
    transaction_type: "Payment", category_id: null, category_name: null,
    merchant_id: null, merchant_name: null, account_id: "acct-2",
    account_name: "Chase Checking", balance: null, memo: null,
    loan_id: "loan-1", loan_name: "Lake House Mortgage", tags: [],
    created_at: "2026-04-01T10:00:00Z",
  },
];

const CANDIDATES: LoanTransaction[] = [
  {
    id: "cand-1", transaction_date: "2026-06-01",
    description: "ROCKET MTG PAYMENT JUN", amount: -2528.27,
    account_name: "Chase Checking",
  },
  {
    id: "cand-2", transaction_date: "2026-06-02",
    description: "SOME OTHER CHARGE", amount: -99.0,
    account_name: "Chase Checking",
  },
];

function mockGets({ linked = LINKED_TXNS, detail = LOAN_DETAIL }: { linked?: CashTransaction[]; detail?: LoanDetail } = {}) {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/loans") return [BASE_LOAN] as never;
    if (path === "/loans/loan-1/candidate_transactions") return CANDIDATES as never;
    if (path === "/loans/loan-1") return detail as never;
    if (path === "/cash_transactions?loan_id=loan-1") return linked as never;
    return [] as never;
  });
}

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

  mockGets();
});

describe("LoanDetail: stats and progress", () => {
  it("renders the header, stat ribbon and payoff progress metrics", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });

    expect((await screen.findAllByText("Lake House Mortgage")).length).toBeGreaterThan(0);
    expect(screen.getByText("Rocket Mortgage")).toBeInTheDocument();
    expect(screen.getByText("mortgage")).toBeInTheDocument();

    // Stat ribbon
    expect(screen.getByText("Outstanding Balance")).toBeInTheDocument();
    expect(screen.getByText("$390,000.00")).toBeInTheDocument();
    expect(screen.getByText("$400,000.00")).toBeInTheDocument();
    expect(screen.getByText("6.500% APR")).toBeInTheDocument();
    expect(screen.getByText("360 mo")).toBeInTheDocument();
    expect(screen.getByText("Payoff Date")).toBeInTheDocument();
    expect(screen.getAllByText(formatDate(SCHEDULE[SCHEDULE.length - 1].payment_date)).length).toBeGreaterThan(0);

    // Payoff progress: (400,000 - 390,000) / 400,000
    expect(screen.getByText("2.5% paid")).toBeInTheDocument();
    expect(screen.getByText("Principal Paid")).toBeInTheDocument();
    expect(screen.getByText("$10,000.00")).toBeInTheDocument();
    expect(screen.getByText("Interest Paid")).toBeInTheDocument();
    expect(screen.getByText("$50,678.48")).toBeInTheDocument();
    expect(screen.getByText("$60,678.48")).toBeInTheDocument();
    expect(screen.getByText("$510,181.00")).toBeInTheDocument();

    // Linked account
    expect(screen.getByText("Mortgage Checking")).toBeInTheDocument();
  });

  it("shows an error message when the loan fails to load", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/loans/missing") throw new Error("HTTP 404");
      return [] as never;
    });

    renderApp({ initialPath: "/loans/missing", initialToken: "tok" });
    expect(await screen.findByText("Failed to load loan.")).toBeInTheDocument();
  });
});

describe("LoanDetail: amortization schedule", () => {
  it("renders the first 24 rows and expands to show the full schedule", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });

    expect(await screen.findByText("Amortization Schedule")).toBeInTheDocument();
    expect(screen.getByText("30 payments")).toBeInTheDocument();

    // Row 1: principal $362, interest $2,166, balance $399,900
    expect(screen.getByText("$399,900.00")).toBeInTheDocument();
    expect(screen.getByText("$362.00")).toBeInTheDocument();
    expect(screen.getByText("$2,166.00")).toBeInTheDocument();

    // Row 24 is the last visible row; row 25 is collapsed
    expect(screen.getByText("$397,600.00")).toBeInTheDocument();
    expect(screen.queryByText("$397,500.00")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Show all 30 payments" }));

    expect(screen.getByText("$397,500.00")).toBeInTheDocument();
    expect(screen.getByText("$397,000.00")).toBeInTheDocument(); // row 30
    expect(screen.getByRole("button", { name: "Show fewer" })).toBeInTheDocument();
  });
});

describe("LoanDetail: linked payments", () => {
  it("renders linked transactions fetched by loan_id", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });

    expect(await screen.findByText("Linked Payments")).toBeInTheDocument();

    // Two payment rows render with their amounts. Note: the table shows the
    // loan name (tx.loan_name) in the description cell for loan-linked
    // transactions, not the raw bank description — current product behavior.
    const amounts = await screen.findAllByText("-$2,528.27");
    expect(amounts).toHaveLength(2);
    // Breadcrumb + 2 rows
    expect(screen.getAllByText("Lake House Mortgage")).toHaveLength(3);
    expect(screen.getAllByText(formatDate(LINKED_TXNS[0].transaction_date)).length).toBeGreaterThan(0);

    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?loan_id=loan-1");
  });

  it("shows an empty message when no transactions are linked", async () => {
    mockGets({ linked: [] });

    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    expect(await screen.findByText(/No transactions linked yet/)).toBeInTheDocument();
  });

  it("links a candidate transaction via PATCH", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    await screen.findByText("Linked Payments");

    fireEvent.click(screen.getByRole("button", { name: "Link payment" }));

    // Candidate list is fetched lazily once the picker opens
    expect(await screen.findByText("ROCKET MTG PAYMENT JUN")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/loans/loan-1/candidate_transactions");

    // Search filters the candidate list
    fireEvent.change(screen.getByPlaceholderText("Search transactions…"), { target: { value: "rocket" } });
    expect(screen.queryByText("SOME OTHER CHARGE")).not.toBeInTheDocument();

    fireEvent.click(screen.getByText("ROCKET MTG PAYMENT JUN"));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/cand-1", { loan_id: "loan-1" });
    });
  });
});

describe("LoanDetail: edit actions", () => {
  it("toggles interest-only via PATCH", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    await screen.findByText("Payoff Progress");

    fireEvent.click(screen.getByRole("button", { name: "Amortizing" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/loans/loan-1", { interest_only: true });
    });
  });

  it("shows escrowed taxes and insurance with what's been paid toward each", async () => {
    mockGets({
      detail: {
        ...LOAN_DETAIL,
        monthly_payment: 3000,
        principal_and_interest_payment: 2528.27,
        escrow_property_tax: 350,
        escrow_insurance: 121.73,
        escrow_payment: 471.73,
        property_tax_paid: 8400,
        insurance_paid: 2921.52,
        amortization_schedule: SCHEDULE.map((row) => ({ ...row, payment: 3000, escrow: 471.73 })),
      },
    });
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });

    expect(await screen.findByText("Principal & interest")).toBeInTheDocument();
    expect(screen.getByText("$2,528.27/mo")).toBeInTheDocument();
    expect(screen.getByText("Property taxes")).toBeInTheDocument();
    expect(screen.getByText("$8,400.00 paid to date")).toBeInTheDocument();
    expect(screen.getByText("$2,921.52 paid to date")).toBeInTheDocument();
    expect(screen.getByText("$3,000.00/mo")).toBeInTheDocument();
    expect(screen.queryByText("Other escrow")).toBeNull();

    expect(screen.getByRole("columnheader", { name: "Escrow" })).toBeInTheDocument();
  });

  it("hides the escrow column when the payment has no escrow", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    await screen.findByText("Amortization Schedule");

    expect(screen.queryByRole("columnheader", { name: "Escrow" })).toBeNull();
    expect(screen.getByText(/No escrow recorded/)).toBeInTheDocument();
  });

  it("records the escrow portion of the monthly payment via PATCH", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: "Edit monthly payment" }));
    fireEvent.change(screen.getByLabelText("Monthly payment"), { target: { value: "3000" } });
    fireEvent.change(screen.getByLabelText("Property taxes"), { target: { value: "350" } });
    fireEvent.change(screen.getByLabelText("Insurance"), { target: { value: "121.73" } });

    expect(screen.getByText("Principal & interest: $2,528.27/mo")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/loans/loan-1", {
        monthly_payment: 3000,
        escrow_property_tax: 350,
        escrow_insurance: 121.73,
        escrow_other: null,
      });
    });
  });

  it("edits the loan's details via PATCH from the page actions menu", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    await screen.findByText("Payoff Progress");

    await user.click(screen.getByRole("button", { name: /Page actions/i }));
    await user.click(await screen.findByRole("menuitem", { name: "Edit loan" }));

    // Prefilled from the loan; a computed payment stays blank so it keeps computing.
    expect(screen.getByLabelText("Loan name *")).toHaveValue("Lake House Mortgage");
    expect(screen.getByLabelText("Interest rate (APR %) *")).toHaveValue(6.5);
    expect(screen.getByLabelText("Monthly payment")).toHaveValue(null);

    fireEvent.change(screen.getByLabelText("Loan name *"), { target: { value: "Lake House Refi" } });
    fireEvent.change(screen.getByLabelText("Interest rate (APR %) *"), { target: { value: "5.875" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/loans/loan-1", expect.objectContaining({
        name: "Lake House Refi",
        interest_rate: 5.875,
        loan_type: "mortgage",
        original_principal: 400000,
        term_months: 360,
        start_date: "2024-01-15",
        account_id: "acct-1",
        monthly_payment: null,
        interest_only: false,
      }));
    });
    await waitFor(() => expect(screen.queryByRole("button", { name: "Save changes" })).toBeNull());
  });

  it("closes the edit form without saving on cancel", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    await screen.findByText("Payoff Progress");

    await user.click(screen.getByRole("button", { name: /Page actions/i }));
    await user.click(await screen.findByRole("menuitem", { name: "Edit loan" }));
    await user.click(screen.getByRole("button", { name: "Cancel" }));

    expect(screen.queryByRole("button", { name: "Save changes" })).toBeNull();
    expect(apiMock.patch).not.toHaveBeenCalled();
  });

  it("sets a balance anchor via PATCH", async () => {
    const { container } = renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    await screen.findByText("Known Balance");

    // Anchor not set yet
    expect(screen.getByText(/Not set — balance calculated/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Set" }));

    fireEvent.change(screen.getByPlaceholderText("14624.55"), { target: { value: "123456.78" } });
    const dateInput = container.querySelector('input[type="date"]');
    expect(dateInput).not.toBeNull();
    fireEvent.change(dateInput!, { target: { value: "2026-06-15" } });

    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/loans/loan-1", {
        balance_anchor_amount: 123456.78,
        balance_anchor_date: "2026-06-15",
      });
    });
  });

  it("deletes the loan after confirmation and returns to the list", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    await screen.findByText("Payoff Progress");

    // Delete is a destructive item in the header's page-actions menu.
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Delete loan" }));
    expect(await screen.findByText("Delete this loan?")).toBeInTheDocument();

    fireEvent.click(await screen.findByRole("button", { name: "Delete loan" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/loans/loan-1");
    });

    // Navigates back to the loans list
    expect(await screen.findByRole("heading", { name: "Loans" })).toBeInTheDocument();
    expect(screen.queryByText("Payoff Progress")).not.toBeInTheDocument();
  });

  it("cancelling the delete confirmation does not call DELETE", async () => {
    renderApp({ initialPath: "/loans/loan-1", initialToken: "tok" });
    await screen.findByText("Payoff Progress");

    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Delete loan" }));
    await screen.findByText("Delete this loan?");
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    await waitFor(() => {
      expect(screen.queryByText("Delete this loan?")).not.toBeInTheDocument();
    });
    expect(apiMock.delete).not.toHaveBeenCalled();
  });
});
