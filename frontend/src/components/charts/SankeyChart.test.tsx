import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";

interface MockNodeProps {
  x: number; y: number; width: number; height: number; index: number;
  payload: { name: string; value: number; targetNodes: number[] };
}

// Drive the custom node renderer directly: recharts computes the layout, our
// code renders nodes — so the mock plays layout engine.
vi.mock("recharts", () => ({
  Sankey: ({ data, node, children }: {
    data: { nodes: { name: string }[]; links: { value: number }[] };
    node: (props: MockNodeProps) => React.ReactNode;
    children?: React.ReactNode;
  }) => (
    <svg data-testid="sankey" data-links={data.links.length}>
      {data.nodes.map((n, i) => (
        <g key={i}>
          {node({
            x: 10, y: i * 40, width: 10, height: 24, index: i,
            payload: { ...n, value: (i + 1) * 100, targetNodes: i < data.nodes.length - 1 ? [i + 1] : [] },
          })}
        </g>
      ))}
      {children}
    </svg>
  ),
  Rectangle: () => <g data-testid="node-rect" />,
  Tooltip: () => <g data-testid="tooltip" />,
  ResponsiveContainer: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
}));

import { SankeyChart, type SankeyNodeInput, type SankeyLinkInput } from "./SankeyChart";

const NODES: SankeyNodeInput[] = [
  { name: "Payroll", kind: "income_source", merchant_id: "m1" },
  { name: "Income", kind: "hub" },
  { name: "Groceries", kind: "category", category_id: "c1" },
  { name: "Savings", kind: "savings" },
];

const LINKS: SankeyLinkInput[] = [
  { source: 0, target: 1, value: 400 },
  { source: 1, target: 2, value: 250 },
  { source: 1, target: 3, value: 150 },
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

describe("SankeyChart", () => {
  it("renders every node with its name and value label, and passes all links", () => {
    renderWithRouter(<SankeyChart nodes={NODES} links={LINKS} />);

    expect(screen.getByTestId("sankey")).toHaveAttribute("data-links", "3");
    expect(screen.getAllByTestId("node-rect")).toHaveLength(4);
    for (const name of ["Payroll", "Income", "Groceries", "Savings"]) {
      expect(screen.getByText(name)).toBeInTheDocument();
    }
    // Values come from the layout payload (mocked as (i+1)*100), compact currency.
    expect(screen.getByText("$100")).toBeInTheDocument();
    expect(screen.getByText("$400")).toBeInTheDocument();
  });

  it("clicking a node emits the node datum and navigates via linkFor", () => {
    const onSelect = vi.fn();
    renderWithRouter(
      <SankeyChart
        nodes={NODES}
        links={LINKS}
        onSelect={onSelect}
        linkFor={(d) => d.kind === "category" && d.category_id
          ? `/transactions?category_id=${d.category_id}`
          : null}
      />,
    );

    fireEvent.click(screen.getByText("Groceries"));

    expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({
      name: "Groceries",
      kind: "category",
      category_id: "c1",
      value: 300,
    }));
    expect(screen.getByTestId("tx-page")).toBeInTheDocument();
  });

  it("does not navigate for nodes whose linkFor returns null", () => {
    renderWithRouter(
      <SankeyChart nodes={NODES} links={LINKS} linkFor={() => null} />,
    );
    fireEvent.click(screen.getByText("Income"));
    expect(screen.queryByTestId("tx-page")).toBeNull();
    expect(screen.getByTestId("sankey")).toBeInTheDocument();
  });
});
