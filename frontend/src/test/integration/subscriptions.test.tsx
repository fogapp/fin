import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, within, fireEvent } from "@testing-library/react";
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

import { api } from "@/api/client";
import { renderApp } from "@/test/renderApp";
import type { RecurringSeries, SubscriptionDetail, SubscriptionsData, SubscriptionsSummary } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

function series(overrides: Partial<RecurringSeries>): RecurringSeries {
  return {
    id: "s1", name: "Netflix", status: "active", source: "detected", kind: "subscription",
    merchant_id: "m1", description_pattern: null, granularity: "month", quantity: 1,
    anchor: { day_of_month: 15 }, cadence_description: "Monthly on the 15th",
    average_amount: 15.49, last_amount: 15.49, min_amount: 15.49, max_amount: 15.49,
    amount_tolerance: 0.075, monthly_equivalent: 15.49, annual_equivalent: 185.88,
    confidence: 0.95, confidence_label: "high",
    first_charge_date: "2025-07-15", last_charge_date: "2026-06-15", next_expected_date: "2026-07-15",
    occurrences_count: 12, misses_streak: 0, at_risk: false, price_changed_recently: false,
    notes: null, accepted_at: "2026-01-01T00:00:00Z", dismissed_at: null, ended_at: null,
    timeline: [],
    ...overrides,
  };
}

const SUMMARY: SubscriptionsSummary = {
  active_count: 2, suggested_count: 1, lapsed_count: 1,
  monthly_total: 27.07, annual_total: 324.84, month_paid: 15.49, month_remaining: 11.58,
};

const ACTIVE: SubscriptionsData = {
  summary: SUMMARY,
  series: [
    series({}),
    series({
      id: "s2", name: "Water Bill", kind: "bill", granularity: "month", quantity: 3,
      cadence_description: "Every 3 months on the 20th", average_amount: 90,
      monthly_equivalent: 30, annual_equivalent: 360, at_risk: true,
    }),
  ],
};

const SUGGESTED: SubscriptionsData = {
  summary: SUMMARY,
  series: [
    series({
      id: "s3", name: "Hulu", status: "suggested", average_amount: 12.99,
      confidence_label: "medium",
      timeline: [
        { id: "o1", expected_date: "2026-05-01", status: "paid", charged_date: "2026-05-01", amount: 12.99, expected_amount: 12.99, amount_delta: 0, cash_transaction_id: "t1" },
        { id: "o2", expected_date: "2026-06-01", status: "missed", charged_date: null, amount: null, expected_amount: 12.99, amount_delta: null, cash_transaction_id: null },
      ],
    }),
  ],
};

const LAPSED: SubscriptionsData = {
  summary: SUMMARY,
  series: [ series({ id: "s4", name: "Old Gym", status: "lapsed", last_charge_date: "2026-03-01" }) ],
};

const DETAIL: SubscriptionDetail = {
  ...series({}),
  occurrences: [
    { id: "o10", expected_date: "2026-05-15", status: "paid", charged_date: "2026-05-15", amount: 15.49, expected_amount: 15.49, amount_delta: 0, cash_transaction_id: "t10", transaction: { id: "t10", description: "NETFLIX.COM", account_name: "Sapphire" } },
    { id: "o11", expected_date: "2026-06-15", status: "paid_amount_changed", charged_date: "2026-06-16", amount: 17.99, expected_amount: 15.49, amount_delta: 2.5, cash_transaction_id: "t11", transaction: { id: "t11", description: "NETFLIX.COM", account_name: "Sapphire" } },
    { id: "o12", expected_date: "2026-07-15", status: "upcoming", charged_date: null, amount: null, expected_amount: 17.99, amount_delta: null, cash_transaction_id: null },
  ],
};

beforeEach(() => {
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
    if (path === "/subscriptions?status=active") return ACTIVE as never;
    if (path === "/subscriptions?status=suggested") return SUGGESTED as never;
    if (path === "/subscriptions?status=lapsed") return LAPSED as never;
    if (path === "/subscriptions?status=dismissed") return { summary: SUMMARY, series: [] } as never;
    if (path.startsWith("/subscriptions/upcoming")) {
      return { upcoming: [ { occurrence_id: "o12", series_id: "s1", name: "Netflix", expected_date: "2026-07-15", expected_amount: 15.49, status: "upcoming" } ] } as never;
    }
    if (path.startsWith("/subscriptions/calendar")) {
      const month = new URLSearchParams(path.split("?")[1]).get("month") ?? "";
      return {
        month,
        occurrences: [
          { id: "o21", series_id: "s1", name: "Netflix", expected_date: `${month}-05`, status: "paid",
            charged_date: `${month}-05`, amount: -15.49, expected_amount: 15.49, amount_delta: 0, cash_transaction_id: "t21" },
          { id: "o22", series_id: "s2", name: "Water Bill", expected_date: `${month}-12`, status: "missed",
            charged_date: null, amount: null, expected_amount: 80, amount_delta: null, cash_transaction_id: null },
        ],
      } as never;
    }
    if (path === "/subscriptions/s1") return DETAIL as never;
    return [] as never;
  });
});

describe("Subscriptions page", () => {
  it("renders summary stats, the review queue, upcoming strip, and grouped active lists", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Subscriptions" })).toBeInTheDocument();

    // Stat ribbon
    expect(screen.getByText("$27.07")).toBeInTheDocument();
    expect(screen.getByText("Paid This Month")).toBeInTheDocument();

    // Review queue with evidence card
    expect(screen.getByText("Needs Review")).toBeInTheDocument();
    expect(screen.getByText("Hulu")).toBeInTheDocument();
    expect(screen.getByText("medium")).toBeInTheDocument();

    // Upcoming strip
    expect(screen.getByLabelText("Upcoming charges")).toBeInTheDocument();

    // Active groups: Monthly + Quarterly
    expect(screen.getByText("Monthly")).toBeInTheDocument();
    expect(screen.getByText("Quarterly")).toBeInTheDocument();
    expect(screen.getByText("Water Bill")).toBeInTheDocument();
    expect(screen.getByText("missed payment")).toBeInTheDocument();

    // Inactive section
    expect(screen.getByText("Old Gym")).toBeInTheDocument();
  });

  it("switches the upcoming section to a month calendar with status-coded charges", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Subscriptions" });

    const toggle = screen.getByRole("group", { name: "Upcoming view" });
    fireEvent.click(within(toggle).getByText("Calendar"));

    // The calendar fetches the current month and shows both history and misses.
    const monthKey = `${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, "0")}`;
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/subscriptions/calendar?month=${monthKey}`);
    });
    expect(await screen.findByTitle(/Water Bill — missed/)).toBeInTheDocument();
    expect(screen.getByTitle(/Netflix — paid/)).toBeInTheDocument();
    expect(screen.getByText("Missed")).toBeInTheDocument(); // legend

    // Clicking a charge opens its series drawer.
    fireEvent.click(screen.getByTitle(/Netflix — paid/));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/subscriptions/s1");
    });
  });

  it("accepts a suggestion from the review queue", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });
    const user = userEvent.setup();

    const accept = await screen.findByRole("button", { name: /Accept/ });
    await user.click(accept);

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/subscriptions/s3/accept", {});
    });
  });

  it("dismisses a suggestion", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });
    const user = userEvent.setup();

    const dismiss = await screen.findByRole("button", { name: "Dismiss" });
    await user.click(dismiss);

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/subscriptions/s3/dismiss", {});
    });
  });

  it("opens the detail drawer with occurrence history and ends the subscription", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });
    const user = userEvent.setup();

    const monthlyTable = await screen.findByLabelText("Monthly subscriptions");
    await user.click(within(monthlyTable).getByText("Netflix"));

    // Evidence timeline with transaction context and amount-change delta
    expect(await screen.findByText("History")).toBeInTheDocument();
    expect(screen.getAllByText(/NETFLIX\.COM/).length).toBeGreaterThan(0);
    expect(screen.getByText("+$2.50")).toBeInTheDocument();
    expect(screen.getByText("Price History")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "End subscription" }));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/subscriptions/s1/end", {});
    });
  });

  it("shows the empty state when nothing is tracked or suggested", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path.startsWith("/subscriptions/upcoming")) return { upcoming: [] } as never;
      if (path.startsWith("/subscriptions")) {
        return { summary: { ...SUMMARY, active_count: 0, suggested_count: 0, lapsed_count: 0, monthly_total: 0 }, series: [] } as never;
      }
      return [] as never;
    });

    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });
    expect(await screen.findByText(/No subscriptions yet/)).toBeInTheDocument();
  });

  // ── Gaps closed by the frontend/API interaction audit ──────────────────────

  it("edits the series from the drawer via PATCH /subscriptions/:id", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });
    const user = userEvent.setup();

    const monthlyTable = await screen.findByLabelText("Monthly subscriptions");
    await user.click(within(monthlyTable).getByText("Netflix"));

    await user.click(await screen.findByRole("button", { name: "Edit details" }));
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "Netflix Premium" } });
    fireEvent.change(screen.getByLabelText("Amount tolerance %"), { target: { value: "10" } });
    await user.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/subscriptions/s1", expect.objectContaining({
        name: "Netflix Premium",
        kind: "subscription",
        amount_tolerance: 0.1,
        granularity: "month",
        quantity: 1,
      }));
    });
  });

  it("clamps an out-of-range tolerance before sending it", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });

    const monthlyTable = await screen.findByLabelText("Monthly subscriptions");
    fireEvent.click(within(monthlyTable).getByText("Netflix"));

    fireEvent.click(await screen.findByText("Edit details"));
    fireEvent.change(screen.getByLabelText("Amount tolerance %"), { target: { value: "500" } });
    // jsdom does not implicitly submit a form from a click on its submit
    // button, so submit the form the button belongs to.
    fireEvent.submit(screen.getByText("Save").closest("form")!);

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/subscriptions/s1", expect.objectContaining({
        amount_tolerance: 0.9,
      }));
    });
  });

  it("deletes the series (with confirm) via DELETE /subscriptions/:id", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });
    const user = userEvent.setup();

    const monthlyTable = await screen.findByLabelText("Monthly subscriptions");
    await user.click(within(monthlyTable).getByText("Netflix"));

    await user.click(await screen.findByRole("button", { name: "Delete" }));
    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Delete this subscription?")).toBeInTheDocument();
    await user.click(within(dialog).getByRole("button", { name: "Delete" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/subscriptions/s1");
    });
  });

  it("keeps the series when the delete confirm is declined", async () => {
    renderApp({ initialPath: "/subscriptions", initialToken: "tok" });
    const user = userEvent.setup();

    const monthlyTable = await screen.findByLabelText("Monthly subscriptions");
    await user.click(within(monthlyTable).getByText("Netflix"));

    await user.click(await screen.findByRole("button", { name: "Delete" }));
    const dialog = await screen.findByRole("alertdialog");
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
    expect(apiMock.delete).not.toHaveBeenCalled();
  });
});
