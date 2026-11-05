import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

// recharts is heavy and needs real layout; the chart body is exercised via the
// shared LineChart primitive's own tests. Stub recharts to structural markers.
vi.mock("recharts", () => ({
  LineChart: ({ children }: { children: React.ReactNode }) => <div data-testid="line-chart">{children}</div>,
  ComposedChart: ({ children }: { children: React.ReactNode }) => <div data-testid="composed">{children}</div>,
  Line: () => <div data-testid="line" />,
  Area: () => <div data-testid="area" />,
  CartesianGrid: () => <div data-testid="grid" />,
  XAxis: () => <div data-testid="x-axis" />,
  YAxis: () => <div data-testid="y-axis" />,
  Tooltip: () => <div data-testid="tooltip" />,
  Legend: () => <div data-testid="legend" />,
  ReferenceLine: ({ y }: { y?: number }) => <div data-testid="ref-line" data-y={y} />,
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

import { SecurityPriceChart } from "./SecurityPriceChart";
import { cutoffFor, PERIODS } from "@/lib/pricePeriods";

function renderChart(ui: React.ReactElement) {
  return render(<MemoryRouter>{ui}</MemoryRouter>);
}

describe("cutoffFor", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    // Use noon so UTC -> local rollback doesn't cross the date line.
    vi.setSystemTime(new Date("2026-06-15T12:00:00Z"));
  });
  afterEach(() => vi.useRealTimers());

  it("returns null for MAX (no filter)", () => {
    expect(cutoffFor("MAX")).toBeNull();
  });

  it("1M is one month back", () => {
    expect(cutoffFor("1M")).toBe("2026-05-15");
  });

  it("6M is six months back", () => {
    expect(cutoffFor("6M")).toBe("2025-12-15");
  });

  it("YTD is January 1st of the current year", () => {
    expect(cutoffFor("YTD")).toBe("2026-01-01");
  });

  it("1Y is one year back", () => {
    expect(cutoffFor("1Y")).toBe("2025-06-15");
  });

  it("5Y is five years back", () => {
    expect(cutoffFor("5Y")).toBe("2021-06-15");
  });
});

describe("SecurityPriceChart", () => {
  const sampleData: [string, number, number][] = [
    [ "2026-01-01", 100, 1000 ],
    [ "2026-02-01", 110, 1100 ],
    [ "2026-03-01", 120, 1200 ],
  ];

  it("renders one tab per period", () => {
    renderChart(
      <SecurityPriceChart data={sampleData} period="1Y" onPeriodChange={() => {}} />,
    );
    PERIODS.forEach((p) => expect(screen.getByRole("tab", { name: p })).toBeInTheDocument());
  });

  it("renders as a single-series area chart with a period-start reference line", () => {
    renderChart(<SecurityPriceChart data={sampleData} period="MAX" onPeriodChange={() => {}} />);
    expect(screen.getByTestId("area")).toBeInTheDocument();
    // Reference line pinned to the first close in the window (100).
    expect(
      screen.getAllByTestId("ref-line").some((el) => el.getAttribute("data-y") === "100"),
    ).toBe(true);
    // Single series: no legend.
    expect(screen.queryByTestId("legend")).toBeNull();
  });

  it("fires onPeriodChange when a period tab is clicked", () => {
    const onPeriodChange = vi.fn();
    renderChart(<SecurityPriceChart data={sampleData} period="1Y" onPeriodChange={onPeriodChange} />);
    fireEvent.click(screen.getByRole("tab", { name: "6M" }));
    expect(onPeriodChange).toHaveBeenCalledWith("6M");
  });

  it("highlights the active period tab", () => {
    renderChart(<SecurityPriceChart data={sampleData} period="1M" onPeriodChange={() => {}} />);
    expect(screen.getByRole("tab", { name: "1M" })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("tab", { name: "6M" })).toHaveAttribute("aria-selected", "false");
  });

  it("renders toolbarLeft content if supplied", () => {
    renderChart(
      <SecurityPriceChart
        data={sampleData}
        period="1Y"
        onPeriodChange={() => {}}
        toolbarLeft={<span>compare</span>}
      />,
    );
    expect(screen.getByText("compare")).toBeInTheDocument();
  });
});
