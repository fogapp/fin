import { describe, it, expect } from "vitest";
import { render, screen, within } from "@testing-library/react";
import { SpendByMonthTable } from "./SpendByMonthTable";

const data = [
  { month: "2025-10", amount: 100 },
  { month: "2025-11", amount: 200 },
  { month: "2025-12", amount: 300 },
  { month: "2026-01", amount: 400 },
  { month: "2026-02", amount: 500 },
  { month: "2026-03", amount: 600 },
];

describe("SpendByMonthTable", () => {
  it("renders the header row and a row per month (default limit 6)", () => {
    render(<SpendByMonthTable data={data} />);
    expect(screen.getByText("Month")).toBeInTheDocument();
    expect(screen.getByText("Spend")).toBeInTheDocument();
    // Months are reversed and formatted with toLocaleDateString month: short
    expect(screen.getByText("Mar")).toBeInTheDocument();
    expect(screen.getByText("Oct")).toBeInTheDocument();
  });

  it("formats each amount as currency", () => {
    render(<SpendByMonthTable data={[ { month: "2026-01", amount: 1234.56 } ]} />);
    expect(screen.getByText("$1,234.56")).toBeInTheDocument();
  });

  it("respects a smaller limit", () => {
    render(<SpendByMonthTable data={data} limit={2} />);
    expect(screen.queryByText("Oct")).toBeNull();
    expect(screen.getByText("Mar")).toBeInTheDocument();
    expect(screen.getByText("Feb")).toBeInTheDocument();
  });

  it("inserts a year divider when the year changes between rows", () => {
    render(<SpendByMonthTable data={data} limit={6} />);
    // The 2025 divider appears once since 2026 → 2025 happens within the window.
    const dividers = screen.getAllByText("2025");
    expect(dividers.length).toBeGreaterThanOrEqual(1);
  });

  it("renders an empty body when no data is supplied", () => {
    const { container } = render(<SpendByMonthTable data={[]} />);
    expect(within(container.querySelector("tbody")!).queryAllByRole("row")).toHaveLength(0);
  });
});
