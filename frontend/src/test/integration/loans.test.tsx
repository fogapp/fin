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
import type { Loan, LoanDetail } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const MORTGAGE: Loan = {
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
  account_id: null,
  account_name: null,
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

const AUTO_LOAN: Loan = {
  ...MORTGAGE,
  id: "loan-2",
  name: "Honda Civic",
  lender: null,
  merchant_id: "m-honda",
  merchant_name: "Honda Financial",
  loan_type: "auto",
  original_principal: 30000,
  interest_rate: 4.25,
  term_months: 60,
  start_date: "2023-03-10",
  monthly_payment: 556.04,
  status: "paid_off",
  total_scheduled_interest: 3362,
  total_paid: 21000,
  principal_paid: 18000,
  interest_paid: 3000,
  current_balance: 12000,
  payments_count: 36,
};

const LOANS = [MORTGAGE, AUTO_LOAN];

const MORTGAGE_DETAIL: LoanDetail = {
  ...MORTGAGE,
  amortization_schedule: [
    { payment_number: 1, payment_date: "2024-02-15", payment: 2528.27, principal: 361.6, interest: 2166.67, balance: 399638.4 },
    { payment_number: 2, payment_date: "2024-03-15", payment: 2528.27, principal: 363.56, interest: 2164.71, balance: 399274.84 },
  ],
  linked_transactions: [],
};

const NEW_LOAN: Loan = {
  ...MORTGAGE,
  id: "loan-new",
  name: "Test Loan",
  lender: null,
  loan_type: "auto",
  original_principal: 25000,
  interest_rate: 5.5,
  term_months: 60,
  current_balance: 25000,
  principal_paid: 0,
  interest_paid: 0,
  total_paid: 0,
  payments_count: 0,
};

const NEW_LOAN_DETAIL: LoanDetail = {
  ...NEW_LOAN,
  amortization_schedule: [],
  linked_transactions: [],
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
    if (path === "/loans") return LOANS as never;
    if (path === "/loans/loan-1") return MORTGAGE_DETAIL as never;
    if (path === "/loans/loan-new") return NEW_LOAN_DETAIL as never;
    return [] as never;
  });
});

describe("Loans: list page", () => {
  it("renders loan cards with balances, rates and payoff progress", async () => {
    renderApp({ initialPath: "/loans", initialToken: "tok" });

    expect(await screen.findByText("Lake House Mortgage")).toBeInTheDocument();
    expect(screen.getByText("Honda Civic")).toBeInTheDocument();

    // Lender / merchant subtitle
    expect(screen.getByText("Rocket Mortgage")).toBeInTheDocument();
    expect(screen.getByText("Honda Financial")).toBeInTheDocument();

    // Remaining balances
    expect(screen.getByText("$390,000.00")).toBeInTheDocument();
    expect(screen.getByText("$12,000.00")).toBeInTheDocument();

    // Rate + monthly payment line and progress percentage
    expect(screen.getByText(/6\.500% APR · \$2,528\.27\/mo/)).toBeInTheDocument();
    expect(screen.getByText(/4\.250% APR/)).toBeInTheDocument();
    expect(screen.getByText("2.5% paid off")).toBeInTheDocument();   // (400,000 − 390,000) / 400,000
    expect(screen.getByText("60.0% paid off")).toBeInTheDocument();  // (30,000 − 12,000) / 30,000

    // Type badges and non-active status badge
    expect(screen.getByText("mortgage")).toBeInTheDocument();
    expect(screen.getByText("auto")).toBeInTheDocument();
    expect(screen.getByText("paid off")).toBeInTheDocument();

    expect(apiMock.get).toHaveBeenCalledWith("/loans");
  });

  it("shows summary totals for outstanding balance, monthly payments and active count", async () => {
    renderApp({ initialPath: "/loans", initialToken: "tok" });

    await screen.findByText("Lake House Mortgage");

    expect(screen.getByText("Total Outstanding")).toBeInTheDocument();
    expect(screen.getByText("$402,000.00")).toBeInTheDocument(); // 390,000 + 12,000

    // Monthly payments only sum active loans (paid_off Honda excluded)
    expect(screen.getByText("Monthly Payments")).toBeInTheDocument();
    expect(screen.getByText("$2,528.27")).toBeInTheDocument();

    expect(screen.getByText("Active Loans")).toBeInTheDocument();
    expect(screen.getByText("1")).toBeInTheDocument();
  });

  it("shows an empty state when there are no loans", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/loans", initialToken: "tok" });
    expect(await screen.findByText(/No loans yet/)).toBeInTheDocument();
    expect(screen.queryByText("Total Outstanding")).not.toBeInTheDocument();
  });

  it("navigates to the loan detail page when a card is clicked", async () => {
    renderApp({ initialPath: "/loans", initialToken: "tok" });

    fireEvent.click(await screen.findByText("Lake House Mortgage"));

    expect(await screen.findByText("Payoff Progress")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/loans/loan-1");
  });

  it("creates a loan via the form and navigates to the new loan's detail page", async () => {
    apiMock.post.mockResolvedValue(NEW_LOAN as never);

    renderApp({ initialPath: "/loans", initialToken: "tok" });
    await screen.findByText("Lake House Mortgage");

    // "New loan" lives in the page-actions menu in the header.
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "New loan" }));

    fireEvent.change(await screen.findByLabelText("Loan name *"), { target: { value: "Test Loan" } });
    fireEvent.change(screen.getByLabelText("Original principal *"), { target: { value: "25000" } });
    fireEvent.change(screen.getByLabelText("Interest rate (APR %) *"), { target: { value: "5.5" } });
    fireEvent.change(screen.getByLabelText("Term (months) *"), { target: { value: "60" } });
    fireEvent.change(screen.getByLabelText("Start date *"), { target: { value: "2026-01-01" } });

    fireEvent.click(screen.getByRole("button", { name: "Create loan" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/loans", expect.objectContaining({
        name: "Test Loan",
        loan_type: "auto",
        original_principal: 25000,
        interest_rate: 5.5,
        term_months: 60,
        start_date: "2026-01-01",
        interest_only: false,
      }));
    });

    // onCreated navigates to /loans/:id of the created loan
    expect(await screen.findByText("Payoff Progress")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/loans/loan-new");
  });

  it("offers escrow fields for a mortgage and posts them with the loan", async () => {
    apiMock.post.mockResolvedValue(NEW_LOAN as never);

    renderApp({ initialPath: "/loans", initialToken: "tok" });
    await screen.findByText("Lake House Mortgage");

    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "New loan" }));

    // Escrow only applies to mortgages.
    expect(screen.queryByLabelText("Property taxes (monthly)")).toBeNull();
    fireEvent.change(await screen.findByLabelText("Type *"), { target: { value: "mortgage" } });

    fireEvent.change(screen.getByLabelText("Loan name *"), { target: { value: "House" } });
    fireEvent.change(screen.getByLabelText("Original principal *"), { target: { value: "400000" } });
    fireEvent.change(screen.getByLabelText("Interest rate (APR %) *"), { target: { value: "6.5" } });
    fireEvent.change(screen.getByLabelText("Term (months) *"), { target: { value: "360" } });
    fireEvent.change(screen.getByLabelText("Start date *"), { target: { value: "2026-01-01" } });
    fireEvent.change(screen.getByLabelText("Monthly payment"), { target: { value: "3000" } });
    fireEvent.change(screen.getByLabelText("Property taxes (monthly)"), { target: { value: "350" } });
    fireEvent.change(screen.getByLabelText("Insurance (monthly)"), { target: { value: "121.73" } });

    fireEvent.click(screen.getByRole("button", { name: "Create loan" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/loans", expect.objectContaining({
        loan_type: "mortgage",
        monthly_payment: 3000,
        escrow_property_tax: 350,
        escrow_insurance: 121.73,
        escrow_other: null,
      }));
    });
  });

  it("toggles the new-loan form open and closed without posting", async () => {
    renderApp({ initialPath: "/loans", initialToken: "tok" });
    await screen.findByText("Lake House Mortgage");
    const user = userEvent.setup();

    expect(screen.queryByPlaceholderText("e.g. 30yr Mortgage")).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "New loan" }));
    expect(await screen.findByPlaceholderText("e.g. 30yr Mortgage")).toBeInTheDocument();

    // While the form is open the menu item reads "Cancel new loan"
    await user.click(screen.getByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Cancel new loan" }));
    await waitFor(() => {
      expect(screen.queryByPlaceholderText("e.g. 30yr Mortgage")).not.toBeInTheDocument();
    });
    expect(apiMock.post).not.toHaveBeenCalled();
  });
});
