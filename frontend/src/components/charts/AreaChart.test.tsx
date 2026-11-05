import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";

// recharts needs real layout; the primitive's stacking/fold/click logic is what
// this file verifies, so stub recharts to structural markers that surface the
// props we care about.
vi.mock("recharts", () => ({
  AreaChart: ({ children, onClick, stackOffset }: {
    children?: React.ReactNode;
    onClick?: (state: { activeLabel?: string }) => void;
    stackOffset?: string;
  }) => (
    <div
      data-testid="area-chart"
      data-stack-offset={stackOffset ?? ""}
      onClick={() => onClick?.({ activeLabel: "2026-03" })}
    >
      {children}
    </div>
  ),
  Area: ({ name, fill, stackId }: { name?: string; fill?: string; stackId?: string }) => (
    <div data-testid="area" data-name={name} data-fill={fill} data-stack-id={stackId} />
  ),
  CartesianGrid: () => <div data-testid="grid" />,
  XAxis: () => <div data-testid="x-axis" />,
  YAxis: ({ domain, tickFormatter }: { domain?: [number, number]; tickFormatter?: (v: number) => string }) => (
    <div data-testid="y-axis" data-domain={domain?.join(",") ?? ""} data-tick={tickFormatter?.(0.25) ?? ""} />
  ),
  Tooltip: () => <div data-testid="tooltip" />,
  Legend: () => <div data-testid="legend" />,
  ReferenceLine: () => <div data-testid="ref-line" />,
  ResponsiveContainer: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
}));

import { AreaChart } from "./AreaChart";
import { LIGHT_SERIES } from "./theme";

const DATA = [
  { month: "2026-02", groceries: 20, dining: 5 },
  { month: "2026-03", groceries: 30, dining: 8 },
];

const SERIES = [{ key: "groceries", label: "Groceries" }, { key: "dining", label: "Dining" }];

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

describe("AreaChart", () => {
  it("stacks every series into one stack, in series order", () => {
    renderWithRouter(<AreaChart data={DATA} series={SERIES} />);

    const areas = screen.getAllByTestId("area");
    expect(areas.map((a) => a.getAttribute("data-name"))).toEqual(["Groceries", "Dining"]);
    expect(new Set(areas.map((a) => a.getAttribute("data-stack-id")))).toEqual(new Set(["stack"]));
    expect(areas[0].getAttribute("data-fill")).toBe(LIGHT_SERIES[0]);
    expect(areas[1].getAttribute("data-fill")).toBe(LIGHT_SERIES[1]);
  });

  it("normalizes to a 0–100% axis in percent mode, and not otherwise", () => {
    const { rerender } = renderWithRouter(<AreaChart data={DATA} series={SERIES} percent />);
    expect(screen.getByTestId("area-chart")).toHaveAttribute("data-stack-offset", "expand");
    expect(screen.getByTestId("y-axis")).toHaveAttribute("data-domain", "0,1");
    expect(screen.getByTestId("y-axis")).toHaveAttribute("data-tick", "25%");

    rerender(<MemoryRouter><AreaChart data={DATA} series={SERIES} /></MemoryRouter>);
    expect(screen.getByTestId("area-chart")).toHaveAttribute("data-stack-offset", "");
    expect(screen.getByTestId("y-axis")).toHaveAttribute("data-domain", "");
  });

  it("folds a 9th+ series into a single Other band (slots never cycle)", () => {
    const series = Array.from({ length: 10 }, (_, i) => ({ key: `s${i}` }));
    const data = [Object.fromEntries([["month", "2026-03"], ...series.map((s) => [s.key, 1])])];

    renderWithRouter(<AreaChart data={data} series={series} />);

    const areas = screen.getAllByTestId("area");
    expect(areas).toHaveLength(9); // 8 slots + "Other"
    expect(areas[8]).toHaveAttribute("data-name", "Other");
    expect(areas[8]).toHaveAttribute("data-fill", "#898781"); // neutral, never a 9th hue
  });

  it("honors an explicit per-series color so a band matches its list row", () => {
    renderWithRouter(
      <AreaChart data={DATA} series={[{ key: "groceries", color: LIGHT_SERIES[4] }, { key: "dining" }]} />,
    );
    expect(screen.getAllByTestId("area")[0]).toHaveAttribute("data-fill", LIGHT_SERIES[4]);
  });

  it("clicking navigates to the URL linkFor builds from the clicked datum", () => {
    const linkFor = vi.fn(() => "/transactions?start_date=2026-03-01");
    renderWithRouter(<AreaChart data={DATA} series={SERIES} linkFor={linkFor} />);

    fireEvent.click(screen.getByTestId("area-chart"));

    expect(linkFor).toHaveBeenCalledWith({ x: "2026-03", row: DATA[1] });
    expect(screen.getByTestId("tx-page")).toBeInTheDocument();
  });

  it("shows a legend only for 2+ series", () => {
    const { rerender } = renderWithRouter(<AreaChart data={DATA} series={[{ key: "groceries" }]} />);
    expect(screen.queryByTestId("legend")).toBeNull();

    rerender(<MemoryRouter><AreaChart data={DATA} series={SERIES} /></MemoryRouter>);
    expect(screen.getByTestId("legend")).toBeInTheDocument();
  });
});
