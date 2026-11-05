import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, fireEvent, waitFor, within } from "@testing-library/react";
import { renderWithRouter } from "@/test/queryClient";
import type { CashflowSankeyData, CashTransaction } from "@/api/types";
import type { Timeframe } from "@/components/charts";

interface MockNodeProps {
  x: number; y: number; width: number; height: number; index: number;
  payload: { name: string; value: number; targetNodes: number[] };
}

// Drive SankeyChart's custom node renderer directly (recharts computes the
// layout, our code renders nodes) so node clicks work without a real layout.
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

// The real PageHeader renders HeaderActions, which needs the AppShell's
// search-palette context — the integration suite covers it; here a stub keeps
// the section renderable standalone.
vi.mock("@/components/layout/PageHeader", () => ({
  PageHeader: ({ title, children }: { title: string; children?: React.ReactNode }) => (
    <div>
      <h1>{title}</h1>
      {children}
    </div>
  ),
}));

vi.mock("@/api/client", () => ({
  api: {
    get: vi.fn(),
    post: vi.fn(() => Promise.resolve({})),
    patch: vi.fn(() => Promise.resolve({})),
    delete: vi.fn(() => Promise.resolve(undefined)),
  },
}));

import { api } from "@/api/client";
import { MoneyFlowSection } from "./MoneyFlowSection";
import { expandFolded } from "./expandFolded";

const apiMock = vi.mocked(api);

const SANKEY: CashflowSankeyData = {
  from: "2025-08-01",
  to: "2026-08-01",
  totals: { income: 40000, spend: 15000, savings: 25000 },
  nodes: [
    { name: "Acme Payroll", kind: "income_source", merchant_id: "m1" },
    { name: "Income", kind: "hub" },
    { name: "Groceries", kind: "category", category_id: "c1" },
    { name: "Savings", kind: "savings" },
    { name: "Food", kind: "category", category_ids: ["c1", "c2"] },
  ],
  links: [
    { source: 0, target: 1, value: 40000 },
    { source: 1, target: 2, value: 15000 },
    { source: 1, target: 3, value: 25000 },
    { source: 1, target: 4, value: 5000 },
  ],
  common: {
    totals: { income: 40000, spend: 9000, savings: 31000 },
    nodes: [
      { name: "Acme Payroll", kind: "income_source", merchant_id: "m1" },
      { name: "Income", kind: "hub" },
      { name: "Groceries", kind: "category", category_id: "c1" },
      { name: "Savings", kind: "savings" },
    ],
    links: [
      { source: 0, target: 1, value: 40000 },
      { source: 1, target: 2, value: 9000 },
      { source: 1, target: 3, value: 31000 },
    ],
    outlier_transaction_ids: ["tx-outlier"],
  },
};

function tx(overrides: Partial<CashTransaction>): CashTransaction {
  return {
    id: "x", source: "credit_card", transaction_date: "2026-06-15",
    transfer_id: null, transfer_kind: null, transfer_include_in_spend: null,
    post_date: null, description: "X", amount: -10,
    transaction_type: "Sale", category_id: "c1", category_name: "Groceries",
    merchant_id: null, merchant_name: null,
    account_id: "a1", account_name: "Everyday Checking",
    balance: null, memo: null, loan_id: null, loan_name: null, tags: [],
    created_at: "2026-06-15T12:00:00Z",
    ...overrides,
  } as CashTransaction;
}

const TRANSACTIONS: CashTransaction[] = [
  tx({ id: "tx-1", description: "COSTCO WHSE #123", amount: -180.22 }),
  tx({ id: "tx-outlier", description: "APPLIANCE SUPERSTORE", amount: -4800 }),
];

const TIMEFRAME: Timeframe = {
  preset: "1y",
  setPreset: vi.fn(),
  setCustom: vi.fn(),
  customRange: null,
  options: [{ key: "1y", label: "1Y", description: "Last 12 months", from: "2025-08-01", to: "2026-08-01" }],
  description: "Last 12 months",
  from: "2025-08-01",
  to: "2026-08-01",
};

function renderSection() {
  return renderWithRouter(
    <MoneyFlowSection timeframe={TIMEFRAME} scope={{}} onScopeChange={vi.fn()} />,
  );
}

beforeEach(() => {
  sessionStorage.clear();
  apiMock.get.mockReset();
  apiMock.get.mockImplementation(async (path: string) => {
    if (path.startsWith("/cashflow/sankey")) return SANKEY as never;
    if (path.startsWith("/cash_transactions")) return TRANSACTIONS as never;
    if (path === "/preferences") return { data: {} } as never;
    return [] as never;
  });
});

describe("MoneyFlowSection", () => {
  it("clicking a category node reveals the transaction table scoped to it, and clicking again clears it", async () => {
    renderSection();

    fireEvent.click(await screen.findByText("Groceries"));

    expect(await screen.findByText("Transactions · Groceries")).toBeInTheDocument();
    expect(await screen.findByText("COSTCO WHSE #123")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith(
      expect.stringContaining("limit=1000&start_date=2025-08-01&end_date=2026-08-01&category_id=c1"),
      expect.anything(),
    );

    fireEvent.click(screen.getByText("Groceries"));
    expect(screen.queryByText("Transactions · Groceries")).toBeNull();
  });

  it("clicking an income source scopes the table to its merchant", async () => {
    renderSection();

    fireEvent.click(await screen.findByText("Acme Payroll"));

    expect(await screen.findByText("Transactions · Acme Payroll")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith(
      expect.stringContaining("merchant_id=m1"),
      expect.anything(),
    );
  });

  it("hub and savings nodes are not selectable", async () => {
    renderSection();

    // "Income"/"Savings" also label ribbon stats — scope to the chart.
    const sankey = await screen.findByTestId("sankey");
    fireEvent.click(within(sankey).getByText("Income"));
    fireEvent.click(within(sankey).getByText("Savings"));

    expect(screen.queryByText(/^Transactions ·/)).toBeNull();
  });

  it("switching the split to Merchant re-queries with dimension=merchant", async () => {
    renderSection();
    await screen.findByTestId("sankey");

    const split = screen.getByRole("group", { name: "Flow split" });
    fireEvent.click(within(split).getByText("Merchant"));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(expect.stringContaining("dimension=merchant"));
    });
  });

  it("clicking a group node filters the table by the group's category ids", async () => {
    renderSection();

    fireEvent.click(await screen.findByText("Food"));

    expect(await screen.findByText("Transactions · Food")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith(
      expect.stringContaining("category_ids=c1%2Cc2"),
      expect.anything(),
    );
  });

  it("Common mode shows the outlier-excluded graph and drops flagged rows from the table", async () => {
    renderSection();
    await screen.findByText("Groceries");

    const toggle = screen.getByRole("group", { name: "Flow transactions" });
    fireEvent.click(within(toggle).getByText("Common"));

    // Ribbon swaps to the common totals (compact currency).
    expect(screen.getByText("$9K")).toBeInTheDocument();
    expect(screen.getByText("$31K")).toBeInTheDocument();

    fireEvent.click(screen.getByText("Groceries"));
    expect(await screen.findByText("COSTCO WHSE #123")).toBeInTheDocument();
    expect(screen.queryByText("APPLIANCE SUPERSTORE")).toBeNull();
  });

  it("clicking Other spending expands its folded rows, and Collapse folds them back", async () => {
    const members = Array.from({ length: 12 }, (_, i) => ({ name: `Tail ${i + 1}`, value: 10, category_id: `t${i + 1}` }));
    const folded: CashflowSankeyData = {
      ...SANKEY,
      nodes: [...SANKEY.nodes, { name: "Other spending", kind: "category", members }],
      links: [...SANKEY.links, { source: 1, target: 5, value: 120 }],
    };
    apiMock.get.mockImplementation(async (path: string) => {
      if (path.startsWith("/cashflow/sankey")) return folded as never;
      return [] as never;
    });
    renderSection();

    fireEvent.click(await screen.findByText("Other spending"));

    // First step reveals ten; the last two stay folded under Other spending.
    expect(screen.getByText("Tail 10")).toBeInTheDocument();
    expect(screen.queryByText("Tail 11")).toBeNull();
    expect(screen.queryByText(/^Transactions ·/)).toBeNull();

    // A revealed row drills like any other category.
    fireEvent.click(screen.getByText("Tail 3"));
    expect(await screen.findByText("Transactions · Tail 3")).toBeInTheDocument();

    fireEvent.click(screen.getByText("Other spending"));
    expect(screen.getByText("Tail 12")).toBeInTheDocument();
    expect(screen.queryByText("Other spending")).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Collapse" }));
    expect(screen.getByText("Other spending")).toBeInTheDocument();
    expect(screen.queryByText("Tail 1")).toBeNull();
  });
});

describe("expandFolded", () => {
  it("splits a folded node's link across revealed rows and the remaining fold", () => {
    const { nodes, links } = expandFolded(
      [
        { name: "Payroll", kind: "income_source" },
        { name: "Other income", kind: "income_source", members: [
          { name: "Refund", value: 30, merchant_id: "m9" },
          { name: "Interest", value: 20 },
        ] },
        { name: "Income", kind: "hub" },
        { name: "Rent", kind: "category", category_id: "c1" },
      ],
      [
        { source: 0, target: 2, value: 100 },
        { source: 1, target: 2, value: 50 },
        { source: 2, target: 3, value: 150 },
      ],
      { income_source: 1, category: 5 },
    );

    expect(nodes.map((n) => n.name)).toEqual(["Payroll", "Refund", "Other income", "Income", "Rent"]);
    expect(nodes[1]).toEqual({ name: "Refund", kind: "income_source", merchant_id: "m9" });
    expect(nodes[2].members).toEqual([{ name: "Interest", value: 20 }]);
    expect(links).toEqual([
      { source: 0, target: 3, value: 100 },
      { source: 1, target: 3, value: 30 },
      { source: 2, target: 3, value: 20 },
      { source: 3, target: 4, value: 150 },
    ]);
  });
});
