import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { StatRibbon } from "./StatRibbon";

describe("StatRibbon", () => {
  it("renders the label + value for each stat", () => {
    render(<StatRibbon stats={[
      { label: "Net worth", value: "$1.2M" },
      { label: "Cash",       value: "$30K" },
    ]} />);

    expect(screen.getByText("Net worth")).toBeInTheDocument();
    expect(screen.getByText("$1.2M")).toBeInTheDocument();
    expect(screen.getByText("Cash")).toBeInTheDocument();
    expect(screen.getByText("$30K")).toBeInTheDocument();
  });

  it("renders empty when no stats are supplied", () => {
    const { container } = render(<StatRibbon stats={[]} />);
    expect(container.querySelectorAll("span.flex.shrink-0").length).toBe(0);
  });

  it("formats a positive change with a + prefix and one decimal", () => {
    render(<StatRibbon stats={[ { label: "x", value: "$1", change: 12.345 } ]} />);
    expect(screen.getByText("+12.3%")).toBeInTheDocument();
  });

  it("formats a negative change with the native - prefix", () => {
    render(<StatRibbon stats={[ { label: "x", value: "$1", change: -3.2 } ]} />);
    expect(screen.getByText("-3.2%")).toBeInTheDocument();
  });

  it("renders a 0 change with a + prefix", () => {
    render(<StatRibbon stats={[ { label: "x", value: "$1", change: 0 } ]} />);
    expect(screen.getByText("+0.0%")).toBeInTheDocument();
  });

  it("omits the change badge when change is null/undefined", () => {
    render(<StatRibbon stats={[ { label: "x", value: "$1" } ]} />);
    expect(screen.queryByText(/%/)).toBeNull();
  });

  it("applies the positive highlight color", () => {
    render(<StatRibbon stats={[ { label: "x", value: "$1", highlight: "positive" } ]} />);
    expect(screen.getByText("$1")).toHaveClass("text-positive");
  });

  it("applies the negative highlight color", () => {
    render(<StatRibbon stats={[ { label: "x", value: "$1", highlight: "negative" } ]} />);
    expect(screen.getByText("$1")).toHaveClass("text-negative");
  });

  it("renders a link when href is set, plain span otherwise", () => {
    render(
      <MemoryRouter>
        <StatRibbon stats={[
          { label: "CC Txns", value: "42", href: "/stats/cc_transaction_count" },
          { label: "Plain", value: "$1" },
        ]} />
      </MemoryRouter>,
    );

    const link = screen.getByRole("link");
    expect(link).toHaveAttribute("href", "/stats/cc_transaction_count");
    expect(link).toContainElement(screen.getByText("CC Txns"));
    expect(screen.getByText("Plain").closest("a")).toBeNull();
  });
});
