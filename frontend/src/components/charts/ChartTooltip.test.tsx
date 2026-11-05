import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { ChartTooltip } from "./ChartTooltip";

const PAYLOAD = [
  { name: "Groceries", dataKey: "groceries", value: 650, color: "#2a78d6" },
  { name: "Dining", dataKey: "dining", value: 250, stroke: "#1baf7a" },
  { name: "Travel", dataKey: "travel", value: 0, fill: "#eda100" },
];

describe("ChartTooltip", () => {
  it("renders nothing when inactive or empty", () => {
    const { container: c1 } = render(<ChartTooltip active={false} payload={PAYLOAD} label="2026-03" />);
    expect(c1).toBeEmptyDOMElement();
    const { container: c2 } = render(<ChartTooltip active payload={[]} label="2026-03" />);
    expect(c2).toBeEmptyDOMElement();
  });

  it("lists every series row with its value and adds a Total row", () => {
    render(<ChartTooltip active payload={PAYLOAD} label="2026-03" />);

    expect(screen.getByText("Groceries")).toBeInTheDocument();
    expect(screen.getByText("$650.00")).toBeInTheDocument();
    expect(screen.getByText("Dining")).toBeInTheDocument();
    expect(screen.getByText("$250.00")).toBeInTheDocument();
    expect(screen.getByText("Travel")).toBeInTheDocument();
    expect(screen.getByText("Total")).toBeInTheDocument();
    expect(screen.getByText("$900.00")).toBeInTheDocument();
  });

  it("formats the header label and values through the given formatters", () => {
    render(
      <ChartTooltip
        active
        payload={[PAYLOAD[0]]}
        label="2026-03"
        labelFormat={(l) => `Month ${l}`}
        valueFormat={(v) => `${v} units`}
      />,
    );
    expect(screen.getByText("Month 2026-03")).toBeInTheDocument();
    expect(screen.getByText("650 units")).toBeInTheDocument();
  });

  it("omits the series name and Total for a single series", () => {
    render(<ChartTooltip active payload={[PAYLOAD[0]]} label="2026-03" />);
    expect(screen.queryByText("Groceries")).toBeNull();
    expect(screen.getByText("$650.00")).toBeInTheDocument();
    expect(screen.queryByText("Total")).toBeNull();
  });

  it("drops zero rows when hideZero is set", () => {
    render(<ChartTooltip active payload={PAYLOAD} label="2026-03" hideZero />);
    expect(screen.queryByText("Travel")).toBeNull();
    expect(screen.getByText("Groceries")).toBeInTheDocument();
  });

  it("appends each row's share of the total when withShare is set", () => {
    render(<ChartTooltip active payload={PAYLOAD} label="2026-03" withShare />);

    // Amounts stay readable on a normalized chart; the share sits beside them.
    expect(screen.getByText("$650.00")).toBeInTheDocument();
    expect(screen.getByText("72%")).toBeInTheDocument();
    expect(screen.getByText("28%")).toBeInTheDocument();
    expect(screen.getByText("$900.00")).toBeInTheDocument(); // Total stays absolute
  });

  it("skips the share rather than dividing by a zero total", () => {
    render(
      <ChartTooltip
        active
        withShare
        label="2026-03"
        payload={[{ name: "A", dataKey: "a", value: 5 }, { name: "B", dataKey: "b", value: -5 }]}
      />,
    );
    expect(screen.queryByText(/%$/)).toBeNull();
  });

  it("supports a total override (e.g. a precomputed Net row)", () => {
    render(
      <ChartTooltip active payload={PAYLOAD} label="2026-03" totalLabel="Net" totalValue={123.45} />,
    );
    expect(screen.getByText("Net")).toBeInTheDocument();
    expect(screen.getByText("$123.45")).toBeInTheDocument();
  });

  it("escapes untrusted series names (React default escaping, no innerHTML)", () => {
    render(
      <ChartTooltip
        active
        payload={[
          { name: "<img src=x onerror=alert(1)>", dataKey: "a", value: 1 },
          { name: "Safe", dataKey: "b", value: 2 },
        ]}
        label="<b>label</b>"
      />,
    );
    // The markup renders as literal text, not elements.
    expect(screen.getByText("<img src=x onerror=alert(1)>")).toBeInTheDocument();
    expect(screen.getByText("<b>label</b>")).toBeInTheDocument();
    expect(document.querySelector("img")).toBeNull();
    expect(document.querySelector("b")).toBeNull();
  });
});
