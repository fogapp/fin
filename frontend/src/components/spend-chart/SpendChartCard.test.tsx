import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithRouter } from "@/test/queryClient";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { builtinOption, timeframeRange, type Timeframe } from "@/components/charts";
import { SpendChartCard } from "./SpendChartCard";
import { useSpendChartControls } from "./useSpendChartControls";
import type { SpendChartScope, SpendTotals } from "./SpendChartCard";
import type { SpendBreakdownData } from "@/api/types";

const apiMock = vi.mocked(api);

/** "yyyy-mm" key for the month `offset` months before the current one. */
function monthKey(offset: number): string {
  const now = new Date();
  const d = new Date(now.getFullYear(), now.getMonth() - offset, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

const THIS_MONTH = monthKey(0);
const LAST_MONTH = monthKey(1);

const BREAKDOWN: SpendBreakdownData = {
  from: `${LAST_MONTH}-01`,
  to: `${THIS_MONTH}-28`,
  monthly_spend: { [`${LAST_MONTH}-01`]: 2500, [`${THIS_MONTH}-01`]: 2000 },
  monthly_spend_common: { [`${LAST_MONTH}-01`]: 2500, [`${THIS_MONTH}-01`]: 1500 },
  category: {
    series: [{ id: "cat-groceries", name: "Groceries" }, { id: "other", name: "Other" }],
    months: {
      [`${LAST_MONTH}-01`]: { "cat-groceries": 2300, other: 200 },
      [`${THIS_MONTH}-01`]: { "cat-groceries": 1800, other: 200 },
    },
  },
  category_common: {
    series: [{ id: "cat-groceries", name: "Groceries" }, { id: "other", name: "Other" }],
    months: {
      [`${LAST_MONTH}-01`]: { "cat-groceries": 2300, other: 200 },
      [`${THIS_MONTH}-01`]: { "cat-groceries": 1300, other: 200 },
    },
  },
  merchant: {
    series: [{ id: "mer-costco", name: "Costco" }, { id: "other", name: "Other" }],
    months: {
      [`${LAST_MONTH}-01`]: { "mer-costco": 2100, other: 400 },
      [`${THIS_MONTH}-01`]: { "mer-costco": 1700, other: 300 },
    },
  },
  merchant_common: {
    series: [{ id: "mer-costco", name: "Costco" }, { id: "other", name: "Other" }],
    months: {
      [`${LAST_MONTH}-01`]: { "mer-costco": 2100, other: 400 },
      [`${THIS_MONTH}-01`]: { "mer-costco": 1200, other: 300 },
    },
  },
};

/** Test host: real controls hook + a fixed 1y timeframe, like a page would wire. */
function Host({ scope, totals, showSeriesToggle, showTimeframeSelector }: {
  scope?: SpendChartScope;
  totals?: SpendTotals;
  showSeriesToggle?: boolean;
  showTimeframeSelector?: boolean;
}) {
  const controls = useSpendChartControls();
  const { from, to } = timeframeRange("1y");
  const timeframe: Timeframe = {
    preset: "1y", setPreset: () => {}, setCustom: () => {}, customRange: null,
    options: [builtinOption("1y")], description: "Last 12 months", from, to,
  };
  return (
    <SpendChartCard
      scope={scope}
      timeframe={timeframe}
      controls={controls}
      totals={totals}
      showSeriesToggle={showSeriesToggle}
      showTimeframeSelector={showTimeframeSelector}
    />
  );
}

const breakdownCalls = () =>
  apiMock.get.mock.calls.map((c) => c[0] as string).filter((p) => p.startsWith("/cashflow/spend_breakdown"));

beforeEach(() => {
  vi.clearAllMocks();
  apiMock.get.mockResolvedValue(BREAKDOWN as never);
});

describe("SpendChartCard", () => {
  it("is self-sufficient: fetches the scoped breakdown immediately when no totals are preloaded", async () => {
    renderWithRouter(<Host scope={{ tagId: "tag-1" }} />);

    const { from, to } = timeframeRange("1y");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/spend_breakdown?from=${from}&to=${to}&tag_id=tag-1`);
    });
    // Total mode by default — no split subtitle, no scale toggle.
    expect(screen.getByText("Monthly Spend")).toBeInTheDocument();
    expect(screen.queryByRole("group", { name: "Spend scale" })).not.toBeInTheDocument();
  });

  it("passes a category scope through to the endpoint", async () => {
    renderWithRouter(<Host scope={{ categoryId: "cat-food" }} />);

    const { from, to } = timeframeRange("1y");
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(`/cashflow/spend_breakdown?from=${from}&to=${to}&category_id=cat-food`);
    });
  });

  it("with preloaded totals, defers the breakdown fetch until a split is picked", async () => {
    const user = userEvent.setup();
    renderWithRouter(
      <Host totals={{ spend: BREAKDOWN.monthly_spend, common: BREAKDOWN.monthly_spend_common }} />,
    );

    expect(breakdownCalls()).toHaveLength(0);

    await user.click(within(screen.getByRole("group", { name: "Spend split" })).getByText("Category"));

    await waitFor(() => expect(breakdownCalls()).toHaveLength(1));
    expect(await screen.findByText(/Each month's spend by category · top 8/)).toBeInTheDocument();
  });

  it("shows the scale toggle only for a split, and describes shares in the subtitle", async () => {
    const user = userEvent.setup();
    renderWithRouter(<Host />);

    await user.click(within(screen.getByRole("group", { name: "Spend split" })).getByText("Merchant"));
    await user.click(within(await screen.findByRole("group", { name: "Spend scale" })).getByText("%"));

    expect(screen.getByText(/Share of each month's spend by merchant/)).toBeInTheDocument();
  });

  it("renders the in-card series and timeframe controls only when asked", async () => {
    renderWithRouter(<Host showSeriesToggle showTimeframeSelector />);

    expect(screen.getByRole("group", { name: "Spend series" })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Timeframe" })).toBeInTheDocument();
    await waitFor(() => expect(breakdownCalls()).toHaveLength(1));
  });

  it("hides the in-card series and timeframe controls by default", async () => {
    renderWithRouter(<Host />);

    expect(screen.queryByRole("group", { name: "Spend series" })).not.toBeInTheDocument();
    expect(screen.queryByRole("group", { name: "Timeframe" })).not.toBeInTheDocument();
    await waitFor(() => expect(breakdownCalls()).toHaveLength(1));
  });

  it("shows an empty state rather than an all-gray stack when nothing is attributed", async () => {
    apiMock.get.mockResolvedValue({
      ...BREAKDOWN,
      merchant: { series: [{ id: "other", name: "Other" }], months: { [`${THIS_MONTH}-01`]: { other: 2000 } } },
      merchant_common: { series: [{ id: "other", name: "Other" }], months: { [`${THIS_MONTH}-01`]: { other: 1500 } } },
    } as never);

    const user = userEvent.setup();
    renderWithRouter(<Host />);

    await user.click(within(screen.getByRole("group", { name: "Spend split" })).getByText("Merchant"));

    expect(await screen.findByText("No merchant spending")).toBeInTheDocument();
    expect(screen.getByText("Nothing to split up in this timeframe.")).toBeInTheDocument();
  });

  it("compact: renders bare Total bars from the scoped endpoint over a default 24-month window", async () => {
    const { container } = renderWithRouter(
      <SpendChartCard variant="compact" scope={{ merchantId: "mer-costco" }} />,
    );

    // No timeframe prop: the window defaults to the last 24 months, matching
    // the hand-rolled fillLastMonths charts this variant replaced.
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(
        `/cashflow/spend_breakdown?from=${monthKey(23)}-01&merchant_id=mer-costco`,
      );
    });
    await waitFor(() => {
      expect(container.querySelector(".recharts-responsive-container")).toBeInTheDocument();
    });
    // No card chrome or mode controls — the page section brings its own header.
    expect(screen.queryByText("Monthly Spend")).not.toBeInTheDocument();
    expect(screen.queryByRole("group", { name: "Spend split" })).not.toBeInTheDocument();
    expect(screen.queryByRole("group", { name: "Spend scale" })).not.toBeInTheDocument();
  });

  it("compact: surfaces a retryable error when the fetch fails", async () => {
    apiMock.get.mockRejectedValue(new Error("boom"));
    renderWithRouter(<SpendChartCard variant="compact" scope={{ accountId: "a1" }} />);

    expect(await screen.findByText("Failed to load spending")).toBeInTheDocument();
  });

  it("surfaces a retryable error when the breakdown fetch fails", async () => {
    apiMock.get.mockRejectedValue(new Error("boom"));
    renderWithRouter(<Host />);

    expect(await screen.findByText("Failed to load spending")).toBeInTheDocument();

    apiMock.get.mockResolvedValue(BREAKDOWN as never);
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: /try again/i }));

    await waitFor(() => {
      expect(screen.queryByText("Failed to load spending")).not.toBeInTheDocument();
    });
  });
});
