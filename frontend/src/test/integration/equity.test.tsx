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
    api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api, clearToken } from "@/api/client";
import { renderApp } from "@/test/renderApp";
import type { EquitySummary, ExercisePlan, TaxProfile } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin", include_unvested_equity: false },
};

const SUMMARY: EquitySummary = {
  companies: [
    {
      id: "co1",
      name: "Initech",
      public_company: false,
      security_id: null,
      ticker: null,
      c_corp: true,
      qsbs_candidate: true,
      preferred_price: null,
      notes: null,
      share_price: 12.5,
      latest_fmv: { id: "f1", price_per_share: 12.5, effective_date: "2026-03-01", source: "409a", stale: false },
      fmv_entries: [{ id: "f1", price_per_share: 12.5, effective_date: "2026-03-01", source: "409a" }],
      grants: [
        {
          id: "g1",
          label: "ISO-2024-1",
          grant_type: "iso",
          grant_date: "2024-02-01",
          vesting_commencement_date: "2024-02-01",
          quantity: 4800,
          strike_price: 2.5,
          early_exercisable: false,
          double_trigger: false,
          expiration_date: "2034-02-01",
          pte_window_days: 90,
          vesting_interval: "monthly",
          vesting_occurrences: 48,
          cliff_installments: 12,
          custom_tranches: null,
          notes: null,
          vested_quantity: 2900,
          unvested_quantity: 1900,
          exercised_quantity: 1000,
          settled_quantity: 0,
          sold_quantity: 0,
          vested_value: 29000,
          unvested_value: 19000,
          next_vest: { date: "2026-08-01", quantity: 100 },
          tranches: [
            { date: "2025-02-01", quantity: 1200, vested: true },
            { date: "2026-08-01", quantity: 100, vested: false },
          ],
          events: [
            { id: "ev1", kind: "exercise", occurred_on: "2025-06-15", quantity: 1000, share_price: 8,
              method: "cash", buyer_type: null, election_83b: false, election_83b_date: null,
              shares_withheld: null, notes: null },
          ],
        },
      ],
    },
  ],
  totals: {
    vested_value: 29000,
    unvested_value: 19000,
    upcoming_vests: [
      { date: "2026-08-01", quantity: 100, value: 1000, grant_id: "g1", grant_label: "ISO-2024-1",
        grant_type: "iso", company_id: "co1", company_name: "Initech" },
    ],
  },
};

const YEAR = new Date().getFullYear();

const TAX_PROFILE: TaxProfile = {
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

const PLAN: ExercisePlan = {
  tax_year: YEAR,
  figures_status: { federal: "final", state: "projected" },
  share_price: 12.5,
  strike_price: 2.5,
  exercisable_quantity: 1900,
  crossover: { shares: 1399, spread: 13990, binding: "federal" },
  simulation: {
    quantity: 1399, spread: 13990, federal_amt: 0, california_amt: 0,
    exercise_cost: 3497.5, total_cash_needed: 3497.5, marginal_rate_next_share: 0.26,
  },
  curve: [
    { quantity: 0, federal_amt: 0, california_amt: 0, total: 0 },
    { quantity: 950, federal_amt: 0, california_amt: 0, total: 0 },
    { quantity: 1900, federal_amt: 4200, california_amt: 800, total: 5000 },
  ],
  scenarios: {
    hold: { federal: 0, california: 0, note: "AMT is largely recoverable as a credit in the sale year." },
    same_year_sale: { federal: 4400, california: 1300, proceeds: 17487.5 },
    qualifying_sale: {
      exercise_year: { federal: 0, california: 0 },
      sale_year: { federal: 2100, california: 1000 },
    },
  },
  safe_harbor: {
    federal: { status: "covered", required: 99000, set_aside: 0, due: `${YEAR + 1}-04-15`, method: "prior_year_110" },
    california: { status: "covered", note: "ISO exercise does not raise CA AGI" },
  },
  stress: { drop_pct: 60, price_after: 5, share_value_after: 6995, tax_still_owed: 0, underwater: 0 },
  nso_gap: null,
  escape_hatch_deadline: `${YEAR}-12-31`,
  exclusions: ["Net investment income tax (3.8%)", "Multi-state allocation"],
  profile: TAX_PROFILE,
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

  apiMock.post.mockImplementation(async (path: string) => {
    if (path.includes("/exercise_plan")) return PLAN as never;
    return {} as never;
  });
  apiMock.put.mockResolvedValue(TAX_PROFILE as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/equity/summary") return SUMMARY as never;
    if (path.startsWith("/tax_profile")) return TAX_PROFILE as never;
    return [] as never;
  });
});

describe("Equity page", () => {
  it("renders the ribbon, upcoming vests, company card and grants", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Equity", level: 1 })).toBeInTheDocument();

    // Stat ribbon: vested, after-tax at the default 30% haircut, unvested
    // (findBy — the loading skeleton also renders the page header)
    expect(await screen.findByText("Vested value")).toBeInTheDocument();
    // $29,000 appears in the ribbon and again as the grant row's vested value
    expect(screen.getAllByText("$29,000.00").length).toBeGreaterThan(0);
    expect(screen.getByText("After tax (~30%)")).toBeInTheDocument();
    expect(screen.getByText("$20,300.00")).toBeInTheDocument();
    expect(screen.getByText("$19,000.00")).toBeInTheDocument();

    // Upcoming vests
    expect(screen.getByRole("heading", { name: "Upcoming vests" })).toBeInTheDocument();
    expect(screen.getByText("100 sh")).toBeInTheDocument();

    // Company card with FMV context and QSBS badge
    expect(screen.getByRole("heading", { name: "Initech" })).toBeInTheDocument();
    expect(screen.getByText("Private")).toBeInTheDocument();
    expect(screen.getByText("QSBS")).toBeInTheDocument();
    expect(screen.getByText(/\$12\.50\/sh/)).toBeInTheDocument();

    // Grant row
    expect(screen.getByText("ISO-2024-1")).toBeInTheDocument();
    expect(screen.getByText("60%")).toBeInTheDocument(); // 2900/4800 vested
  });

  it("expands a grant to show the vesting schedule and events", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });
    fireEvent.click(await screen.findByText("ISO-2024-1"));

    expect(screen.getByText("Vesting schedule")).toBeInTheDocument();
    expect(screen.getByText("Exercised")).toBeInTheDocument();
    expect(screen.getByText(/@ \$8\.00/)).toBeInTheDocument();
    expect(screen.getByText(/Next:/)).toBeInTheDocument();
  });

  it("recomputes grant values at a what-if price client-side", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });
    await screen.findByText("ISO-2024-1");

    fireEvent.change(screen.getByLabelText("Scenario price for Initech"), { target: { value: "20" } });

    // ISO intrinsic at $20: (20 − 2.5) × 2900 vested = $50,750; unvested (20−2.5)×1900 = $33,250
    expect(screen.getByText("$50,750.00")).toBeInTheDocument();
    expect(screen.getByText(/\+\$33,250\.00 unvested/)).toBeInTheDocument();
  });

  it("creates a company through the dialog", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });
    // "Add company" now lives in the page-actions dropdown in the header
    await userEvent.setup().click(await screen.findByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /Add company/i }));

    fireEvent.change(screen.getByLabelText(/Company name/), { target: { value: "Hooli" } });
    fireEvent.change(screen.getByLabelText("Price per share"), { target: { value: "3.25" } });
    fireEvent.change(screen.getByLabelText("Effective date"), { target: { value: "2026-06-01" } });
    fireEvent.click(screen.getByRole("button", { name: "Add company" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/equity/companies", expect.objectContaining({
        name: "Hooli",
        public_company: false,
        initial_fmv: { price_per_share: 3.25, effective_date: "2026-06-01", source: "409a" },
      }));
    });
  });

  it("creates a grant with a flat vesting schedule", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });
    fireEvent.click(await screen.findByRole("button", { name: "Grant" }));

    fireEvent.change(screen.getByLabelText(/Quantity/), { target: { value: "1000" } });
    fireEvent.change(screen.getByLabelText(/Grant date/), { target: { value: "2026-01-15" } });
    fireEvent.change(screen.getByLabelText(/Strike price/), { target: { value: "5" } });
    fireEvent.click(screen.getByRole("button", { name: "Add grant" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/equity/grants", expect.objectContaining({
        equity_company_id: "co1",
        grant_type: "iso",
        quantity: 1000,
        strike_price: 5,
        vesting_interval: "monthly",
        vesting_occurrences: 48,
        cliff_installments: 12,
      }));
    });
  });

  it("records an exercise event from an expanded grant", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });
    fireEvent.click(await screen.findByText("ISO-2024-1"));
    fireEvent.click(screen.getByRole("button", { name: "Record event" }));

    fireEvent.change(screen.getByLabelText(/^Date/), { target: { value: "2026-07-01" } });
    fireEvent.change(screen.getByLabelText(/^Shares/), { target: { value: "500" } });
    fireEvent.change(screen.getByLabelText(/FMV per share/), { target: { value: "12.5" } });
    fireEvent.click(screen.getByRole("button", { name: "Record event" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/equity/grants/g1/events", expect.objectContaining({
        kind: "exercise",
        occurred_on: "2026-07-01",
        quantity: 500,
        share_price: 12.5,
        method: "cash",
      }));
    });
  });

  it("deletes a grant through the confirm dialog", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });
    fireEvent.click(await screen.findByText("ISO-2024-1"));
    fireEvent.click(screen.getByRole("button", { name: "Delete grant" }));
    fireEvent.click(await screen.findByRole("button", { name: "Delete" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/equity/grants/g1");
    });
  });

  it("opens the exercise planner with crossover, cash, scenarios, and safe harbor", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });
    fireEvent.click(await screen.findByText("ISO-2024-1"));
    fireEvent.click(screen.getByRole("button", { name: "Plan exercise" }));

    // Hero crossover number
    expect(await screen.findByText("1,399")).toBeInTheDocument();
    expect(screen.getByText(/\$0 additional AMT/)).toBeInTheDocument();
    expect(screen.getByText(/Binding constraint: federal AMT/)).toBeInTheDocument();

    // Plan POST used the grant endpoint
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith(
        "/equity/grants/g1/exercise_plan",
        expect.objectContaining({ tax_year: YEAR, stress_drop_pct: 60 }),
      );
    });

    // Cash breakdown, scenarios, safe harbor, assumptions
    expect(screen.getByText("Total cash needed")).toBeInTheDocument();
    expect(screen.getByText("Exercise & hold")).toBeInTheDocument();
    expect(screen.getByText("Sell same year")).toBeInTheDocument();
    expect(screen.getByText("Qualifying sale")).toBeInTheDocument();
    expect(screen.getByText(/Federal safe harbor:/)).toBeInTheDocument();
    expect(screen.getByText(/Escape hatch/)).toBeInTheDocument();
    // "not tax advice" also appears in the page's haircut footer — allow both
    expect(screen.getAllByText(/not tax advice/).length).toBeGreaterThan(1);
    expect(screen.getByText(/projected/)).toBeInTheDocument();
  });

  it("re-plans with an explicit quantity when the input changes", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });
    fireEvent.click(await screen.findByText("ISO-2024-1"));
    fireEvent.click(screen.getByRole("button", { name: "Plan exercise" }));
    await screen.findByText("1,399");

    fireEvent.change(screen.getByLabelText("Shares to exercise"), { target: { value: "500" } });

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith(
        "/equity/grants/g1/exercise_plan",
        expect.objectContaining({ quantity: 500 }),
      );
    });
  });

  it("asks for the tax profile first when it is incomplete", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/equity/summary") return SUMMARY as never;
      if (path.startsWith("/tax_profile")) {
        return { ...TAX_PROFILE, projected_wages: 0, complete: false, persisted: false } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/equity", initialToken: "tok" });
    fireEvent.click(await screen.findByText("ISO-2024-1"));
    fireEvent.click(screen.getByRole("button", { name: "Plan exercise" }));

    expect(await screen.findByText(/needs a \d+ tax profile/)).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText(new RegExp(`Projected ${YEAR} wages`)), { target: { value: "400000" } });
    fireEvent.click(screen.getByRole("button", { name: "Save profile" }));

    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/tax_profile", expect.objectContaining({
        tax_year: YEAR,
        projected_wages: 400000,
        state: "CA",
      }));
    });
  });

  it("toggles counting unvested shares toward net worth", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    const toggle = await screen.findByRole("checkbox", { name: /unvested shares toward net worth/i });
    expect(toggle).not.toBeChecked();

    fireEvent.click(toggle);

    await waitFor(() =>
      expect(apiMock.patch).toHaveBeenCalledWith("/households/h1", { include_unvested_equity: true })
    );
  });

  it("shows the empty state with a create CTA when no companies exist", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/equity/summary") return { companies: [], totals: { vested_value: 0, unvested_value: 0, upcoming_vests: [] } } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/equity", initialToken: "tok" });
    expect(await screen.findByText("No equity yet.")).toBeInTheDocument();
  });

  // ── Gaps closed by the frontend/API interaction audit ──────────────────────

  it("edits a company through the dialog via PATCH /equity/companies/:id", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    fireEvent.click(await screen.findByLabelText("Edit Initech"));
    expect(await screen.findByText("Edit company")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText(/Company name/), { target: { value: "Initech Inc" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/equity/companies/co1", expect.objectContaining({
        name: "Initech Inc",
        public_company: false,
        c_corp: true,
        qsbs_candidate: true,
      }));
    });
  });

  it("does not send an initial_fmv when editing an existing company", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    fireEvent.click(await screen.findByLabelText("Edit Initech"));
    fireEvent.click(await screen.findByRole("button", { name: "Save changes" }));

    await waitFor(() => expect(apiMock.patch).toHaveBeenCalled());
    const payload = apiMock.patch.mock.calls[0][1] as Record<string, unknown>;
    expect(payload).not.toHaveProperty("initial_fmv");
  });

  it("deletes a company through the confirm dialog via DELETE /equity/companies/:id", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    fireEvent.click(await screen.findByLabelText("Delete Initech"));
    expect(await screen.findByText("Delete Initech?")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/equity/companies/co1");
    });
  });

  it("does not delete the company when the confirm is declined", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    fireEvent.click(await screen.findByLabelText("Delete Initech"));
    fireEvent.click(await screen.findByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
    expect(apiMock.delete).not.toHaveBeenCalled();
  });

  it("edits a grant through the dialog via PATCH /equity/grants/:id", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    fireEvent.click(await screen.findByText("ISO-2024-1"));
    fireEvent.click(screen.getByLabelText("Edit grant"));

    fireEvent.change(await screen.findByLabelText(/Quantity/), { target: { value: "5200" } });
    fireEvent.click(screen.getByRole("button", { name: "Save changes" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/equity/grants/g1", expect.objectContaining({
        quantity: 5200,
      }));
    });
  });

  it("records a new share value via POST /equity/companies/:id/fmv_entries", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: "Record FMV" }));
    expect(await screen.findByText(/Record share value/)).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText(/Price per share/), { target: { value: "15.75" } });
    fireEvent.change(screen.getByLabelText(/Effective date/), { target: { value: "2026-08-01" } });
    fireEvent.click(screen.getByRole("button", { name: "Record" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/equity/companies/co1/fmv_entries", {
        price_per_share: 15.75,
        effective_date: "2026-08-01",
        source: "409a",
      });
    });
  });

  it("keeps the share-value dialog's save disabled until price and date are both set", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: "Record FMV" }));
    expect(await screen.findByText(/Record share value/)).toBeInTheDocument();

    const save = screen.getByRole("button", { name: "Record" });
    expect(save).toBeDisabled();

    fireEvent.change(screen.getByLabelText(/Price per share/), { target: { value: "15.75" } });
    expect(save).toBeDisabled();

    fireEvent.change(screen.getByLabelText(/Effective date/), { target: { value: "2026-08-01" } });
    expect(save).toBeEnabled();
  });

  it("deletes a recorded event via DELETE /equity/events/:id", async () => {
    renderApp({ initialPath: "/equity", initialToken: "tok" });

    fireEvent.click(await screen.findByText("ISO-2024-1"));
    fireEvent.click(await screen.findByLabelText("Delete event"));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/equity/events/ev1");
    });
  });
});
