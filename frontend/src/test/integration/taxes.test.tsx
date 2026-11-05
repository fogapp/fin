import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, fireEvent, within } from "@testing-library/react";

vi.mock("@simplewebauthn/browser", () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api, clearToken } from "@/api/client";
import { renderApp } from "@/test/renderApp";
import type { TaxProfile, TaxReport } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const YEAR = new Date().getFullYear();

const PROFILE: TaxProfile = {
  tax_year: YEAR,
  filing_status: "single",
  state: "CA",
  state_name: "California",
  state_tax_source: "modeled",
  projected_state_tax: null,
  projected_wages: 400000,
  other_ordinary_income: 0,
  ltcg_qd_income: 0,
  itemizing: false,
  salt_paid: 0,
  itemized_other: 0,
  prior_year_total_tax: 90000,
  prior_year_agi: 380000,
  ytd_withholding_federal: 100000,
  ytd_withholding_state: 30000,
  amt_credit_carryforward_federal: 0,
  amt_credit_carryforward_ca: 0,
  complete: true,
  persisted: true,
};

const REPORT: TaxReport = {
  year: YEAR,
  generated_at: `${YEAR}-07-06T00:00:00Z`,
  profile: PROFILE,
  income: {
    kind: "fact",
    wages: { kind: "estimate", amount: 400000, note: "from the tax profile" },
    interest: 1200,
    dividends: 5400,
    realized_gains: {
      short_term: -2000,
      long_term: 12000,
      total: 10000,
      by_security: [{ security_id: "s1", label: "VTI", short_term: -2000, long_term: 12000, total: 10000 }],
    },
    equity_comp: {
      ordinary_income: 15000,
      iso_amt_spread: 30000,
      events: [],
      notes: [],
    },
    adjustments: {
      kind: "record",
      total: 8000,
      items: [
        { id: "adj1", kind: "income", jurisdiction: "both", label: "K-1 — Fund II", amount: 8000, bucket: null, notes: null },
      ],
    },
  },
  deductions: {
    kind: "fact",
    mortgage_interest: { total: 18000, loans: [{ loan_id: "l1", name: "Home mortgage", interest_paid: 18000 }], note: null },
    charitable: {
      total: 900,
      gifts: [
        { transaction_id: "t1", date: `${YEAR}-03-10`, description: "Red Cross", amount: 600, receipt: false },
        { transaction_id: "t2", date: `${YEAR}-05-02`, description: "Food bank", amount: 300, receipt: true },
      ],
    },
    salt: { kind: "record", state_withholding: 30000, state_estimated_payments: 4000, amount: 34000, note: null },
    adjustments: { kind: "record", total: 0, items: [] },
  },
  liability: {
    kind: "estimate",
    assumptions: {
      figures_status: { federal: "final", state: "projected" },
      notes: ["All dividends treated as qualified until 1099s arrive"],
    },
    federal: {
      regular_tax: 95000, amt: 9000, total: 104000, credits: 0, taxable_income: 383900,
      effective_rate: 0.26, marginal_ordinary_rate: 0.35,
      withheld_and_paid: 104000, projected_refund_or_owed: 0,
    },
    state: {
      regular_tax: 33000, amt: 2000, total: 35000, credits: 0, taxable_income: 394460,
      effective_rate: 0.0875, marginal_ordinary_rate: 0.103,
      withheld_and_paid: 34000, projected_refund_or_owed: -1000,
    },
    credits: { kind: "record", total: 0, items: [] },
    total_liability: 139000,
    bracket_headroom: {
      to_next_federal_bracket: { amount: 40000, current_rate: 0.35, next_rate: 0.37 },
      ltcg_zero_headroom: 0,
      note: null,
    },
  },
  payments: {
    kind: "record",
    federal: {
      withholding: 100000,
      estimated: [{ id: "p1", jurisdiction: "federal", paid_on: `${YEAR}-06-10`, amount: 4000, quarter: "Q2", notes: null }],
      total: 104000,
    },
    state: {
      withholding: 30000,
      estimated: [{ id: "p2", jurisdiction: "state", paid_on: `${YEAR}-06-10`, amount: 4000, quarter: "Q2", notes: null }],
      total: 34000,
    },
    due_dates: [
      { jurisdiction: "federal", label: "Q1", date: `${YEAR}-04-15`, weight: 0.25, paid_in_window: 0, status: "past" },
      { jurisdiction: "federal", label: "Q2", date: `${YEAR}-06-15`, weight: 0.25, paid_in_window: 4000, status: "past" },
      { jurisdiction: "federal", label: "Q3", date: `${YEAR}-09-15`, weight: 0.25, paid_in_window: 0, status: "upcoming" },
    ],
    safe_harbor: {
      federal: { status: "covered", required_annual: 99000, paid: 104000 },
      state: { status: "uncovered", required_annual: 99000, paid: 34000 },
    },
  },
  contributions: {
    kind: "fact",
    buckets: [
      { key: "401k", label: "401(k) employee deferral", treatments: ["traditional_401k", "roth_401k"], informational: false, contributed: 20000, transfers_total: 20000, adjustments_total: 0, limit: 24500, percent_of_limit: 81.6, note: null, accounts: [{ id: "acc-401k", name: "Fidelity 401k", tax_treatment: "traditional_401k" }] },
      { key: "ira", label: "IRA / Roth IRA", treatments: ["traditional_ira", "roth_ira"], informational: false, contributed: 0, transfers_total: 0, adjustments_total: 0, limit: 7500, percent_of_limit: 0, note: null, accounts: [] },
      { key: "hsa", label: "HSA", treatments: ["hsa"], informational: false, contributed: 4400, transfers_total: 4400, adjustments_total: 0, limit: 4400, percent_of_limit: 100, note: null, accounts: [{ id: "acc-hsa", name: "HSA Bank", tax_treatment: "hsa" }] },
    ],
    note: null,
  },
  flags: {
    kind: "fact",
    wash_sales: [
      { security_id: "s1", security_label: "VTI", sale_date: `${YEAR}-03-04`, sale_account: "Brokerage", loss: -2000, purchase_date: `${YEAR}-03-20`, purchase_account: "Roth IRA", permanent: true },
    ],
    note: null,
  },
  documents: {
    kind: "record",
    items: [
      { id: "d1", kind: "w2", source_label: "Employer", status: "expected", auto_seeded: true, reference_id: null, notes: null },
      { id: "d2", kind: "1099_consolidated", source_label: "Fidelity", status: "expected", auto_seeded: true, reference_id: null, notes: "corrected versions common into March" },
      { id: "chk-gift", kind: "charitable_receipt", source_label: "Red Cross — $600", status: "expected", auto_seeded: true, reference_id: "t1", notes: null },
    ],
  },
};

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.put.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  apiMock.post.mockResolvedValue({} as never);
  apiMock.put.mockResolvedValue(PROFILE as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path.startsWith("/tax/report")) return REPORT as never;
    if (path.startsWith("/tax/export")) return { report: REPORT } as never;
    if (path.startsWith("/tax_profile")) return PROFILE as never;
    return [] as never;
  });
});

describe("Taxes page", () => {
  it("renders the liability hero with refund/owed and kind badges", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });

    expect(await screen.findByText("Projected amount owed")).toBeInTheDocument();
    expect(screen.getByText("$1,000.00")).toBeInTheDocument(); // fed 0 + state −1000
    expect(screen.getByText("$139,000.00")).toBeInTheDocument();
    expect(screen.getByText(/incl\. \$9,000\.00 AMT/)).toBeInTheDocument();
    expect(screen.getAllByText("Estimate").length).toBeGreaterThan(0);
    expect(screen.getAllByText("From your data").length).toBeGreaterThan(0);
    // Bracket headroom
    expect(screen.getByText(/room before the 37% bracket/)).toBeInTheDocument();
    // Assumptions footer
    expect(screen.getByText(/All dividends treated as qualified/)).toBeInTheDocument();
  });

  it("renders income, deductions, contributions, wash sales, and documents", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    // Income facts
    expect(screen.getByText("Realized gains — long term")).toBeInTheDocument();
    expect(screen.getByText("$12,000.00")).toBeInTheDocument();
    expect(screen.getByText(/ISO spread \(AMT only/)).toBeInTheDocument();
    expect(screen.getByText(/Ordinary income \(NSO exercises/)).toBeInTheDocument();
    expect(screen.getByText("K-1 — Fund II (adjustment)")).toBeInTheDocument();

    // Deductions
    expect(screen.getByText("Home mortgage")).toBeInTheDocument();
    expect(screen.getByText(/Red Cross/)).toBeInTheDocument();

    // Contributions progress
    expect(screen.getByText("401(k) employee deferral")).toBeInTheDocument();
    expect(screen.getByText(/\$20,000\.00 \/ \$24,500\.00/)).toBeInTheDocument();
    // The API sends account objects; the card lists their names.
    expect(screen.getByText("Fidelity 401k")).toBeInTheDocument();

    // Wash sale, permanent (IRA) variant
    expect(screen.getByText(/disallowed permanently/)).toBeInTheDocument();

    // Documents (charitable receipts live in Deductions, not here)
    expect(screen.getByText("Consolidated 1099")).toBeInTheDocument();
    expect(screen.queryByText("Red Cross — $600")).toBeNull();
  });

  it("records an estimated payment through the dialog", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    fireEvent.click(screen.getByRole("button", { name: /Record payment/ }));
    fireEvent.change(screen.getByLabelText(/Paid on/), { target: { value: `${YEAR}-09-10` } });
    fireEvent.change(screen.getByLabelText(/Amount/), { target: { value: "5000" } });
    fireEvent.click(screen.getByRole("button", { name: "Record payment" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/tax/estimated_payments", expect.objectContaining({
        tax_year: YEAR,
        jurisdiction: "federal",
        paid_on: `${YEAR}-09-10`,
        amount: 5000,
      }));
    });
  });

  it("adds an adjustment through the dialog", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    fireEvent.change(screen.getByLabelText(/Label/), { target: { value: "Rental income" } });
    fireEvent.change(screen.getByLabelText(/^Amount/), { target: { value: "24000" } });
    fireEvent.click(screen.getByRole("button", { name: "Add adjustment" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/tax/adjustments", expect.objectContaining({
        tax_year: YEAR,
        kind: "income",
        label: "Rental income",
        amount: 24000,
      }));
    });
  });

  it("toggles a charitable receipt and a document status via PATCH", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    // The receipt checkbox patches the charitable_receipt checklist item
    // linked by reference_id to the gift transaction.
    fireEvent.click(screen.getByLabelText("Receipt on file for Red Cross"));
    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/tax/checklist_items/chk-gift", { status: "received" });
    });

    fireEvent.change(screen.getByLabelText("Status for Fidelity"), { target: { value: "received" } });
    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/tax/checklist_items/d2", { status: "received" });
    });
  });

  it("switches years and refetches the report", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    fireEvent.click(screen.getByRole("button", { name: "Previous year" }));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/tax/report?year=${YEAR - 1}`);
    });
  });

  it("prompts for the tax profile when incomplete, keeping facts visible", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/tax/report")) {
        return { ...REPORT, profile: null, liability: null } as never;
      }
      if (path.startsWith("/tax_profile")) {
        return { ...PROFILE, projected_wages: 0, complete: false, persisted: false } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    expect(await screen.findByText(/unlock the liability estimate/)).toBeInTheDocument();
    expect(screen.queryByText("Projected amount owed")).toBeNull();
    // Facts still render
    expect(screen.getByText("Realized gains — long term")).toBeInTheDocument();
  });

  it("saves a non-California state, requiring its projected state tax", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    fireEvent.click(screen.getByRole("button", { name: new RegExp(`${YEAR} tax profile`) }));
    fireEvent.change(await screen.findByLabelText(/State of residence/), { target: { value: "NY" } });
    expect(screen.getByRole("button", { name: "Save profile" })).toBeDisabled();

    fireEvent.change(screen.getByLabelText(/Projected state tax/), { target: { value: "25000" } });
    fireEvent.click(screen.getByRole("button", { name: "Save profile" }));

    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/tax_profile", expect.objectContaining({
        tax_year: YEAR,
        state: "NY",
        projected_state_tax: 25000,
      }));
    });
  });

  it("labels the state side with the profile's state", async () => {
    const nyProfile: TaxProfile = { ...PROFILE, state: "NY", state_name: "New York", state_tax_source: "entered", projected_state_tax: 35000 };
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/tax/report")) {
        return {
          ...REPORT,
          profile: nyProfile,
          liability: {
            ...REPORT.liability!,
            assumptions: { ...REPORT.liability!.assumptions, figures_status: { federal: "final", state: null } },
            state: { ...REPORT.liability!.state, amt: 0, taxable_income: null, marginal_ordinary_rate: null },
          },
          payments: {
            ...REPORT.payments,
            safe_harbor: { ...REPORT.payments.safe_harbor, state: { status: "unknown", note: "The state safe harbor is only checked for California" } },
          },
        } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    expect(screen.getByText("NY withholding (projected)")).toBeInTheDocument();
    expect(screen.getByText(/New York safe harbor/)).toBeInTheDocument();
    expect(screen.queryByText(/California \(/)).toBeNull();
    expect(screen.queryByText(/FTB/)).toBeNull();
  });

  // ── Gaps closed by the frontend/API interaction audit ──────────────────────

  it("edits an adjustment via PATCH /tax/adjustments/:id", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    fireEvent.click(screen.getByLabelText("Edit K-1 — Fund II"));

    fireEvent.change(await screen.findByLabelText(/Label/), { target: { value: "K-1 — Fund III" } });
    fireEvent.change(screen.getByLabelText(/^Amount/), { target: { value: "9500" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/tax/adjustments/adj1", expect.objectContaining({
        tax_year: YEAR,
        kind: "income",
        label: "K-1 — Fund III",
        amount: 9500,
      }));
    });
  });

  it("removes an adjustment (with confirm) via DELETE /tax/adjustments/:id", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    fireEvent.click(screen.getByLabelText("Remove K-1 — Fund II"));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText('Remove "K-1 — Fund II"?')).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/tax/adjustments/adj1");
    });
  });

  it("keeps the adjustment when the remove confirm is declined", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    fireEvent.click(screen.getByLabelText("Remove K-1 — Fund II"));
    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
    expect(apiMock.delete).not.toHaveBeenCalled();
  });

  it("removes an estimated payment (with confirm) via DELETE /tax/estimated_payments/:id", async () => {
    renderApp({ initialPath: "/taxes", initialToken: "tok" });
    await screen.findByText("Projected amount owed");

    fireEvent.click(screen.getAllByLabelText("Remove payment")[0]);

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Remove this payment record?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/tax/estimated_payments/p1");
    });
  });
});
