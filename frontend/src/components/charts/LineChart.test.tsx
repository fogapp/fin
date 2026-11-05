import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

vi.mock("recharts", () => ({
  LineChart: ({ children, onClick }: {
    children?: React.ReactNode;
    onClick?: (state: { activeLabel?: string }) => void;
  }) => (
    <div data-testid="line-chart" onClick={() => onClick?.({ activeLabel: "2026-01-15" })}>
      {children}
    </div>
  ),
  ComposedChart: ({ children }: { children?: React.ReactNode }) => (
    <div data-testid="composed-chart">{children}</div>
  ),
  Line: ({ name }: { name?: string }) => <div data-testid="line" data-name={name} />,
  Area: ({ name }: { name?: string }) => <div data-testid="area" data-name={name} />,
  CartesianGrid: () => <div data-testid="grid" />,
  XAxis: () => <div data-testid="x-axis" />,
  YAxis: () => <div data-testid="y-axis" />,
  Tooltip: () => <div data-testid="tooltip" />,
  Legend: () => <div data-testid="legend" />,
  ReferenceLine: ({ x }: { x?: string }) => <div data-testid="ref-line" data-x={x} />,
  ResponsiveContainer: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
}));

import { LineChart  } from "./LineChart";
import { curveFor } from "./common";

const DAILY = [
  { date: "2026-01-14", spend: 10, income: 3 },
  { date: "2026-01-15", spend: 12, income: 0 },
];

describe("LineChart", () => {
  it("renders one line per series with a legend for 2+ series", () => {
    render(
      <MemoryRouter>
        <LineChart
          data={DAILY}
          series={[{ key: "spend", label: "Spend" }, { key: "income", label: "Income" }]}
          xKey="date"
        />
      </MemoryRouter>,
    );
    const lines = screen.getAllByTestId("line");
    expect(lines.map((l) => l.getAttribute("data-name"))).toEqual(["Spend", "Income"]);
    expect(screen.getByTestId("legend")).toBeInTheDocument();
  });

  it("renders a single series as an area (no legend) when area is set", () => {
    render(
      <MemoryRouter>
        <LineChart data={DAILY} series={[{ key: "spend", label: "Spend" }]} xKey="date" area />
      </MemoryRouter>,
    );
    expect(screen.getByTestId("area")).toBeInTheDocument();
    expect(screen.queryByTestId("legend")).toBeNull();
  });

  it("draws a reference line at each year boundary", () => {
    render(
      <MemoryRouter>
        <LineChart
          data={[{ month: "2025-12", v: 1 }, { month: "2026-01", v: 2 }, { month: "2026-02", v: 3 }]}
          series={[{ key: "v" }]}
        />
      </MemoryRouter>,
    );
    const boundaries = screen.getAllByTestId("ref-line").filter((el) => el.getAttribute("data-x"));
    expect(boundaries).toHaveLength(1);
    expect(boundaries[0]).toHaveAttribute("data-x", "2026-01");
  });

  it("clicking the crosshair position emits the snapped datum", () => {
    const onSelect = vi.fn();
    render(
      <MemoryRouter>
        <LineChart data={DAILY} series={[{ key: "spend" }, { key: "income" }]} xKey="date" onSelect={onSelect} />
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByTestId("line-chart"));
    expect(onSelect).toHaveBeenCalledWith({
      x: "2026-01-15",
      row: { date: "2026-01-15", spend: 12, income: 0 },
    });
  });
});

describe("curveFor", () => {
  it("draws straight segments for sparse aggregate series", () => {
    expect(curveFor(6)).toBe("linear");   // 6 months of totals
    expect(curveFor(24)).toBe("linear");  // 2 years of monthly points
    expect(curveFor(44)).toBe("linear");
  });

  it("smooths dense daily series where the curve cannot distort", () => {
    expect(curveFor(45)).toBe("monotone");
    expect(curveFor(90)).toBe("monotone");  // 3 months daily
    expect(curveFor(365)).toBe("monotone"); // a year daily
  });
});
