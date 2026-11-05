import { describe, it, expect, beforeEach, vi } from "vitest";
import { act, screen, waitFor, fireEvent, within } from "@testing-library/react";

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
import { monthDateRange } from "@/components/charts";
import { currentMonth, shiftMonth } from "@/pages/budget/budgetMonth";
import { monthLabel } from "@/lib/monthLabel";
import type { BudgetCalendarData, BudgetData, BudgetLine, BudgetSuggestions, CategorySummary } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const THIS_MONTH = currentMonth();
const THIS_YEAR = new Date().getFullYear();

const CATEGORIES: CategorySummary[] = [
  { id: "c1", name: "Home", parent_id: null, transaction_count: 3, budget_kind: "flex" },
  { id: "c2", name: "Groceries", parent_id: null, transaction_count: 40, budget_kind: "flex" },
  { id: "c3", name: "Dining", parent_id: null, transaction_count: 20, budget_kind: "flex" },
  { id: "c4", name: "Gifts", parent_id: null, transaction_count: 5, budget_kind: "flex" },
  { id: "c5", name: "Mortgage", parent_id: "c1", transaction_count: 8, budget_kind: "flex" },
  { id: "c6", name: "Coffee", parent_id: "c2", transaction_count: 10, budget_kind: "flex" },
];

function line(overrides: Partial<BudgetLine>): BudgetLine {
  return {
    id: "bl", category_id: "c", category_name: "C", parent_id: null, parent_name: null,
    period: "monthly", mode: "ongoing", set_in: shiftMonth(THIS_MONTH, -2),
    planned: 0, rollover: false, rollover_amount: 0, actual: 0, month_actual: 0, remaining: 0,
    percent_used: 0, typical: 0, projected: null, rolled_up_children: [],
    ...overrides,
  };
}

const HOME = line({
  id: "bl1", category_id: "c1", category_name: "Home", planned: 1000, actual: 400, month_actual: 400,
  remaining: 600, percent_used: 40, projected: 900,
});
const MORTGAGE = line({
  id: "bl2", category_id: "c5", category_name: "Mortgage", parent_id: "c1", parent_name: "Home",
  planned: 2500, actual: 2500, month_actual: 2500, remaining: 0, percent_used: 100, projected: 2500,
});
const GROCERIES = line({
  id: "bl3", category_id: "c2", category_name: "Groceries", planned: 800, rollover: true, rollover_amount: 50,
  actual: 600, month_actual: 600, remaining: 250, percent_used: 70.6, projected: 1100,
});
const DINING = line({
  id: "bl4", category_id: "c3", category_name: "Dining", planned: 300, mode: "month_only", set_in: THIS_MONTH,
  actual: 90, month_actual: 90, remaining: 210, percent_used: 30, projected: 250,
});
const GIFTS = line({
  id: "bl5", category_id: "c4", category_name: "Gifts", period: "yearly", planned: 1200, actual: 450,
  month_actual: 50, remaining: 750, percent_used: 37.5,
});

function makeBudget(overrides: Partial<BudgetData> = {}): BudgetData {
  return {
    month: THIS_MONTH,
    income: { planned: null, actual: 5200, suggestion: 5800 },
    planned: 4900,
    actual: 3790,
    remaining: 1160,
    left_to_plan: null,
    lines: [MORTGAGE, HOME, GROCERIES, DINING],
    yearly: { planned: 1200, actual: 450, remaining: 750, set_aside: 100, lines: [GIFTS] },
    everything_else: { planned: 300, actual: 200, uncategorized: 40, remaining: 100, projected: 280 },
    pace: { percent_elapsed: 40, current: true },
    forecast: {
      projected: 5030, available: 4950, over_by: 80,
      overages: [{ category_id: "c2", category_name: "Groceries", over: 250 }],
    },
    ...overrides,
  };
}

const EMPTY_BUDGET = makeBudget({
  planned: 0, actual: 0, remaining: 0, lines: [],
  yearly: { planned: 0, actual: 0, remaining: 0, set_aside: 0, lines: [] },
  everything_else: { planned: null, actual: 800, uncategorized: 0, remaining: null, projected: null },
  forecast: null,
});

const SUGGESTIONS: BudgetSuggestions = {
  month: THIS_MONTH,
  categories: [
    {
      category_id: "c1", category_name: "Home", parent_id: null, parent_name: null, budgeted: true,
      typical: 305, suggested: 305, year_total: 30470, recurring_monthly: 0,
      history: [28970, 290, 310, 280, 320, 300].map((actual, i) => ({ month: shiftMonth(THIS_MONTH, i - 6), actual })),
      unusual: [{ id: "t9", transaction_date: `${THIS_YEAR}-06-29`, description: "Design firm", amount: 28970 }],
    },
    {
      category_id: "c2", category_name: "Groceries", parent_id: null, parent_name: null, budgeted: true,
      typical: 790, suggested: 790, year_total: 9500, recurring_monthly: 0, history: [], unusual: [],
    },
    {
      category_id: "c6", category_name: "Coffee", parent_id: "c2", parent_name: "Groceries", budgeted: false,
      typical: 62, suggested: 65, year_total: 700, recurring_monthly: 0, history: [], unusual: [],
    },
  ],
  everything_else: { typical: 410, suggested: 410 },
};

const LINE_HISTORY = {
  category_id: "c1",
  months: [
    { month: shiftMonth(THIS_MONTH, -2), planned: 900, actual: 1750 },
    { month: shiftMonth(THIS_MONTH, -1), planned: 1000, actual: 2050 },
    { month: THIS_MONTH, planned: 1000, actual: 400 },
  ],
};

const CALENDAR: BudgetCalendarData = {
  year: THIS_YEAR,
  months: [THIS_MONTH],
  rows: [
    {
      category_id: "c1", category_name: "Home", parent_id: null, period: "monthly", annual: null,
      months: { [THIS_MONTH]: { planned: 1000, override: false, actual: 400 } },
      total_planned: 1000, total_actual: 400,
    },
    {
      category_id: "c2", category_name: "Groceries", parent_id: null, period: "monthly", annual: null,
      months: { [THIS_MONTH]: { planned: 600, override: true, actual: 750 } },
      total_planned: 600, total_actual: 750,
    },
    {
      category_id: "c4", category_name: "Gifts", parent_id: null, period: "yearly", annual: 1200,
      months: { [THIS_MONTH]: { planned: null, override: false, actual: 50 } },
      total_planned: 1200, total_actual: 50,
    },
  ],
  totals: { [THIS_MONTH]: { planned: 1600, override: false, actual: 1200 } },
};

const TRANSACTIONS = [
  { id: "t1", transaction_date: `${THIS_MONTH}-03`, description: "HARDWARE", amount: -400, merchant_name: "Hardware Co",
    account_name: "Checking", category_id: "c1", category_name: "Home", source: "bank", transaction_type: "Sale",
    budget_excluded: false, tags: [] },
];

let budgetPayload: BudgetData;

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.put.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  budgetPayload = makeBudget();

  apiMock.post.mockResolvedValue({ filled: 3 } as never);
  apiMock.put.mockResolvedValue({} as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path.startsWith("/budget/line_history")) return LINE_HISTORY as never;
    if (path.startsWith("/budget/calendar")) return CALENDAR as never;
    if (path.startsWith("/budget/suggestions")) return SUGGESTIONS as never;
    if (path.startsWith("/budget")) return budgetPayload as never;
    if (path === "/categories") return CATEGORIES as never;
    if (path.startsWith("/cash_transactions")) return TRANSACTIONS as never;
    return [] as never;
  });
});

async function openEditMode() {
  renderApp({ initialPath: "/budget", initialToken: "tok" });
  fireEvent.click(await screen.findByRole("button", { name: /Edit budget/ }));
  await screen.findByRole("region", { name: "Monthly budget amounts" });
}

describe("Budget: tracking a month", () => {
  it("summarizes the month with the forecast, and lists lines with subcategories nested", async () => {
    renderApp({ initialPath: "/budget", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Budget" })).toBeInTheDocument();
    expect(screen.getByText(monthLabel(THIS_MONTH))).toBeInTheDocument();

    const summary = await screen.findByRole("region", { name: "Month summary" });
    expect(summary).toHaveTextContent("$3,790.00");
    expect(summary).toHaveTextContent("of $4,950.00");
    expect(summary).toHaveTextContent("$1,160.00 left");
    expect(summary).toHaveTextContent("Heading $80.00 over by month end — mostly Groceries");

    const monthly = screen.getByRole("region", { name: "Monthly budgets" });
    const rows = within(monthly).getAllByRole("button").map((b) => b.textContent ?? "");
    // Home (with Mortgage nested under it) sorts first on the group total.
    expect(rows[0]).toMatch(/^Home/);
    expect(rows[1]).toMatch(/^Mortgage/);
    expect(within(monthly).getByText(`${new Date(`${THIS_MONTH}-15`).toLocaleDateString("en-US", { month: "short" })} only`)).toBeInTheDocument();
    expect(within(monthly).getByText("On pace for $1,100.00")).toBeInTheDocument();
    expect(within(monthly).getByText("Everything else")).toBeInTheDocument();
    expect(within(monthly).getByText("$200.00 of $300.00")).toBeInTheDocument();

    const yearly = screen.getByRole("region", { name: "Yearly budgets" });
    expect(within(yearly).getByText("$450.00 of $1,200.00")).toBeInTheDocument();
  });

  it("reports how a past month finished", async () => {
    budgetPayload = makeBudget({ forecast: null, pace: { percent_elapsed: 100, current: false }, remaining: 120 });
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    expect(await screen.findByText("Finished $120.00 under budget")).toBeInTheDocument();
  });

  it("offers to set an everything-else budget when there isn't one", async () => {
    budgetPayload = makeBudget({
      everything_else: { planned: null, actual: 200, uncategorized: 0, remaining: null, projected: null },
    });
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    expect(await screen.findByText(/spent in categories without a budget/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Set a budget" }));
    expect(await screen.findByRole("region", { name: "Monthly budget amounts" })).toBeInTheDocument();
  });

  it("steps back a month", async () => {
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    await screen.findByRole("region", { name: "Month summary" });
    fireEvent.click(screen.getByRole("button", { name: "Previous month" }));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/budget?month=${shiftMonth(THIS_MONTH, -1)}`);
    });
  });
});

describe("Budget: drill-down drawer", () => {
  it("opens a line's transactions and recent months", async () => {
    const { from, to } = monthDateRange(THIS_MONTH);
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    fireEvent.click(within(await screen.findByRole("region", { name: "Monthly budgets" })).getAllByRole("button")[0]);

    expect(await screen.findByRole("dialog")).toBeInTheDocument();
    expect(await screen.findByText("Hardware Co")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith(
      `/cash_transactions?category_id=c1&start_date=${from}&end_date=${to}`,
      expect.anything(),
    );
    expect(await screen.findByText("Recent Months")).toBeInTheDocument();
  });

  it("excludes a one-off transaction from budgets", async () => {
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    fireEvent.click(within(await screen.findByRole("region", { name: "Monthly budgets" })).getAllByRole("button")[0]);

    fireEvent.click(await screen.findByRole("button", { name: "Exclude Hardware Co from budgets" }));
    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/cash_transactions/t1", { budget_excluded: true });
    });
  });

  it("turns on rollover from the drawer", async () => {
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    fireEvent.click(within(await screen.findByRole("region", { name: "Monthly budgets" })).getAllByRole("button")[0]);

    fireEvent.click(await screen.findByRole("checkbox"));
    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/line", {
        month: THIS_MONTH, category_id: "c1", rollover: true, mode: "ongoing",
      });
    });
  });

  it("shows a yearly line's transactions for the year so far", async () => {
    const { to } = monthDateRange(THIS_MONTH);
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    fireEvent.click(within(await screen.findByRole("region", { name: "Yearly budgets" })).getByRole("button"));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(
        `/cash_transactions?category_id=c4&start_date=${THIS_YEAR}-01-01&end_date=${to}`,
        expect.anything(),
      );
    });
  });
});

describe("Budget: edit mode", () => {
  it("shows typical spend and the one-off charges it leaves out", async () => {
    await openEditMode();
    expect(await screen.findByText("Typically $305/mo")).toBeInTheDocument();
    expect(screen.getByText(/not counting Design firm \$28,970/)).toBeInTheDocument();
  });

  it("saves an amount from this month on", async () => {
    await openEditMode();
    const input = screen.getByRole("textbox", { name: "Budget for Home" });
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: "1,250" } });
    fireEvent.blur(input);

    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/line", {
        month: THIS_MONTH, category_id: "c1", planned: 1250, mode: "ongoing",
      });
    });
  });

  it("saves an amount for this month only", async () => {
    await openEditMode();
    const toggle = screen.getByRole("group", { name: "Changes apply" });
    fireEvent.click(within(toggle).getByText(/only$/));

    const input = screen.getByRole("textbox", { name: "Budget for Groceries" });
    act(() => input.focus());
    fireEvent.change(input, { target: { value: "1500" } });
    fireEvent.keyDown(input, { key: "Enter" });

    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/line", {
        month: THIS_MONTH, category_id: "c2", planned: 1500, mode: "month_only",
      });
    });
  });

  it("applies the typical month with one click", async () => {
    await openEditMode();
    fireEvent.click(await screen.findByRole("button", { name: "Use $305" }));
    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/line", {
        month: THIS_MONTH, category_id: "c1", planned: 305, mode: "ongoing",
      });
    });
  });

  it("switches a line to yearly, keeping the amount equivalent", async () => {
    await openEditMode();
    fireEvent.change(screen.getByRole("combobox", { name: "How often for Home" }), { target: { value: "yearly" } });
    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/line", {
        month: THIS_MONTH, category_id: "c1", period: "yearly", planned: 12000, mode: "ongoing",
      });
    });
  });

  it("stops budgeting a category after confirmation", async () => {
    await openEditMode();
    fireEvent.click(screen.getByRole("button", { name: "Stop budgeting Dining" }));
    fireEvent.click(await screen.findByRole("button", { name: "Stop budgeting" }));
    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/budget/line", { month: THIS_MONTH, category_id: "c3" });
    });
  });

  it("adds a suggested category at its typical amount", async () => {
    await openEditMode();
    const picker = await screen.findByRole("combobox", { name: "Add a category" });
    expect(within(picker).getByText("Groceries › Coffee — typically $62/mo")).toBeInTheDocument();
    fireEvent.change(picker, { target: { value: "c6" } });
    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/line", {
        month: THIS_MONTH, category_id: "c6", planned: 65, mode: "ongoing",
      });
    });
  });

  it("sets and clears the everything-else amount", async () => {
    await openEditMode();
    const input = screen.getByRole("textbox", { name: "Budget for everything else" });
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: "" } });
    fireEvent.blur(input);
    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/period", { month: THIS_MONTH, other_planned: null });
    });

    fireEvent.click(screen.getByRole("button", { name: "Use $410" }));
    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/period", { month: THIS_MONTH, other_planned: 410 });
    });
  });

  it("sets expected income and shows what's left to plan", async () => {
    budgetPayload = makeBudget({ income: { planned: 6000, actual: 5200, suggestion: 5800 }, left_to_plan: 1000 });
    await openEditMode();
    expect(screen.getByText(/\$1,000.00 of income not budgeted/)).toBeInTheDocument();

    const input = screen.getByRole("textbox", { name: "Expected income" });
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: "6500" } });
    fireEvent.blur(input);
    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/period", { month: THIS_MONTH, income_planned: 6500 });
    });
  });

  it("Done returns to tracking", async () => {
    await openEditMode();
    fireEvent.click(screen.getByRole("button", { name: "Done" }));
    expect(await screen.findByRole("region", { name: "Month summary" })).toBeInTheDocument();
  });
});

describe("Budget: getting started", () => {
  it("suggests a starting budget, then opens edit mode to review it", async () => {
    budgetPayload = EMPTY_BUDGET;
    renderApp({ initialPath: "/budget", initialToken: "tok" });

    expect(await screen.findByText("Set up your budget")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Suggest a starting budget/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/budget/autofill", { month: THIS_MONTH });
    });
    expect(await screen.findByText(/Added 3 categories at their typical amounts/)).toBeInTheDocument();
    expect(await screen.findByRole("region", { name: "Monthly budget amounts" })).toBeInTheDocument();
  });

  it("starts from scratch in edit mode", async () => {
    budgetPayload = EMPTY_BUDGET;
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    fireEvent.click(await screen.findByRole("button", { name: "Start from scratch" }));
    expect(await screen.findByText(/add the few you want to keep an eye on/)).toBeInTheDocument();
  });
});

describe("Budget: year view", () => {
  it("shows the year grid, overruns and yearly rows, and jumps back to a month", async () => {
    renderApp({ initialPath: "/budget", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Budget" });

    fireEvent.click(within(screen.getByRole("group", { name: "Budget view" })).getByText("Year"));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/budget/calendar?year=${THIS_YEAR}`);
    });
    expect(await screen.findByText("Home")).toBeInTheDocument();
    expect(screen.getByText("Yearly")).toBeInTheDocument();
    expect(screen.getByText(/\$1\.2K\/yr/)).toBeInTheDocument();
    expect(screen.getByText(/^\$750/).className).toContain("text-negative");

    fireEvent.click(screen.getByTitle(/Open .* in the month view/));
    expect(await screen.findByRole("region", { name: "Month summary" })).toBeInTheDocument();
  });

  it("sets a one-month amount from a cell", async () => {
    renderApp({ initialPath: "/budget#view=calendar", initialToken: "tok" });
    await screen.findByText("Home");

    fireEvent.click(screen.getByTitle("Set a one-month amount"));
    const input = await screen.findByRole("textbox", { name: /Home budget for/ });
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: "1800" } });
    fireEvent.blur(input);

    await waitFor(() => {
      expect(apiMock.put).toHaveBeenCalledWith("/budget/line", {
        month: THIS_MONTH, category_id: "c1", planned: 1800, mode: "month_only",
      });
    });
  });

  it("clears a one-month amount back to the ongoing budget", async () => {
    renderApp({ initialPath: "/budget#view=calendar", initialToken: "tok" });
    await screen.findByText("Home");

    fireEvent.click(screen.getByTitle(/One-month amount/));
    const input = await screen.findByRole("textbox", { name: /Groceries budget for/ });
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: "" } });
    fireEvent.blur(input);

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/budget/line", {
        month: THIS_MONTH, category_id: "c2", month_only: true,
      });
    });
  });

  it("pages between years", async () => {
    renderApp({ initialPath: "/budget#view=calendar", initialToken: "tok" });
    await screen.findByText("Home");
    fireEvent.click(screen.getByRole("button", { name: "Previous year" }));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/budget/calendar?year=${THIS_YEAR - 1}`);
    });
  });
});
