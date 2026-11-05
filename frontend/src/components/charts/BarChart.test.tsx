import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";

// recharts needs real layout; the primitives' click/legend/fold logic is what
// this file verifies, so stub recharts to structural markers that surface the
// props we care about.
vi.mock("recharts", () => ({
  BarChart: ({ children, onClick }: {
    children?: React.ReactNode;
    onClick?: (state: { activeLabel?: string }) => void;
  }) => (
    <div data-testid="bar-chart" onClick={() => onClick?.({ activeLabel: "2026-03" })}>
      {children}
    </div>
  ),
  Bar: ({ name, fill, children }: { name?: string; fill?: string; children?: React.ReactNode }) => (
    <div data-testid="bar" data-name={name} data-fill={fill}>{children}</div>
  ),
  Cell: () => <div data-testid="cell" />,
  CartesianGrid: () => <div data-testid="grid" />,
  XAxis: () => <div data-testid="x-axis" />,
  YAxis: () => <div data-testid="y-axis" />,
  Tooltip: () => <div data-testid="tooltip" />,
  Legend: () => <div data-testid="legend" />,
  ReferenceLine: () => <div data-testid="ref-line" />,
  ResponsiveContainer: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
}));

import { BarChart } from "./BarChart";
import { assignSeriesColors, LIGHT_SERIES, useChartTheme } from "./theme";

const DATA = [
  { month: "2026-02", spend: 20, income: 5 },
  { month: "2026-03", spend: 30, income: 8 },
];

function renderWithRouter(ui: React.ReactElement) {
  return render(
    <MemoryRouter initialEntries={["/"]}>
      <Routes>
        <Route path="/" element={ui} />
        <Route path="/transactions" element={<div data-testid="tx-page" />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("BarChart", () => {
  it("clicking a column calls onSelect with the x value and full row", () => {
    const onSelect = vi.fn();
    renderWithRouter(
      <BarChart data={DATA} series={[{ key: "spend", label: "Spend" }]} onSelect={onSelect} />,
    );

    fireEvent.click(screen.getByTestId("bar-chart"));

    expect(onSelect).toHaveBeenCalledWith({
      x: "2026-03",
      row: { month: "2026-03", spend: 30, income: 8 },
    });
  });

  it("navigates to the URL linkFor builds from the clicked datum", () => {
    const linkFor = vi.fn(() => "/transactions?start_date=2026-03-01");
    renderWithRouter(
      <BarChart data={DATA} series={[{ key: "spend" }]} linkFor={linkFor} />,
    );

    fireEvent.click(screen.getByTestId("bar-chart"));

    expect(linkFor).toHaveBeenCalledWith(expect.objectContaining({ x: "2026-03" }));
    expect(screen.getByTestId("tx-page")).toBeInTheDocument();
  });

  it("shows a legend only for 2+ series (a title names a single series)", () => {
    const { rerender } = renderWithRouter(
      <BarChart data={DATA} series={[{ key: "spend" }]} />,
    );
    expect(screen.queryByTestId("legend")).toBeNull();

    rerender(
      <MemoryRouter>
        <BarChart data={DATA} series={[{ key: "spend", label: "Spend" }, { key: "income", label: "Income" }]} stacked />
      </MemoryRouter>,
    );
    expect(screen.getByTestId("legend")).toBeInTheDocument();
    expect(screen.getAllByTestId("bar")).toHaveLength(2);
  });

  it("folds a 9th+ series into a single Other series (slots never cycle)", () => {
    const series = Array.from({ length: 10 }, (_, i) => ({ key: `s${i}` }));
    const data = [Object.fromEntries([["month", "2026-03"], ...series.map((s) => [s.key, 1])])];

    renderWithRouter(<BarChart data={data} series={series} stacked />);

    const bars = screen.getAllByTestId("bar");
    expect(bars).toHaveLength(9); // 8 slots + "Other"
    expect(bars[8]).toHaveAttribute("data-name", "Other");
  });

  it("shares one entity→color assignment between chart series (legend keys) and list dots", () => {
    // One assignment per section: the chart's series colors and any adjacent
    // colored list dot for the same entity must resolve identically.
    const names = Array.from({ length: 10 }, (_, i) => `merchant-${i}`);

    function Harness() {
      const theme = useChartTheme();
      const colors = assignSeriesColors(names, theme);
      return (
        <>
          <BarChart
            data={[Object.fromEntries([["month", "2026-03"], ...names.map((n) => [n, 1])])]}
            series={names.map((n) => ({ key: n, color: colors.get(n) }))}
            stacked
          />
          {/* Side list rendering dots from the SAME map */}
          {names.map((n) => (
            <span key={n} data-testid="dot" data-name={n} data-color={colors.get(n) ?? theme.neutral} />
          ))}
          <span data-testid="dot" data-name="not-in-chart" data-color={colors.get("not-in-chart") ?? theme.neutral} />
        </>
      );
    }

    renderWithRouter(<Harness />);

    const bars = screen.getAllByTestId("bar");
    const dots = screen.getAllByTestId("dot");
    const dotColor = (name: string) =>
      dots.find((d) => d.getAttribute("data-name") === name)?.getAttribute("data-color");

    // The 8 slotted entities: chart fill === list dot color (fixed palette order)
    bars.slice(0, 8).forEach((bar, i) => {
      const name = bar.getAttribute("data-name")!;
      expect(bar.getAttribute("data-fill")).toBe(dotColor(name));
      expect(bar.getAttribute("data-fill")).toBe(LIGHT_SERIES[i]);
    });

    // 9th+ entities fold into "Other" in the chart and their dots go neutral —
    // identical color, never a new slot.
    const otherBar = bars.find((b) => b.getAttribute("data-name") === "Other")!;
    expect(otherBar.getAttribute("data-fill")).toBe("#898781");
    expect(dotColor("merchant-8")).toBe("#898781");
    expect(dotColor("merchant-9")).toBe("#898781");
    // A list entry that isn't in the chart at all falls to neutral too.
    expect(dotColor("not-in-chart")).toBe("#898781");
  });

  it("renders per-cell colors for diverging single-series data", () => {
    renderWithRouter(
      <BarChart
        data={[{ month: "2026-02", net: 5 }, { month: "2026-03", net: -7 }]}
        series={[{ key: "net", label: "Net" }]}
        diverging
      />,
    );
    expect(screen.getAllByTestId("cell")).toHaveLength(2);
    expect(screen.getAllByTestId("ref-line").length).toBeGreaterThan(0); // zero baseline
  });
});
