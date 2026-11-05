import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { BenchmarkCombobox } from "./BenchmarkCombobox";

const suggestions = [
  { symbol: "SPY", label: "S&P 500" },
  { symbol: "QQQ", label: "NASDAQ-100" },
  { symbol: "VTI", label: "Vanguard Total Stock Market" },
];

const colors = { SPY: "#ff0000", QQQ: "#00ff00", VTI: "#0000ff" };

describe("BenchmarkCombobox", () => {
  it("renders chips for each selected symbol", () => {
    render(
      <BenchmarkCombobox
        selected={[ "SPY", "QQQ" ]}
        onAdd={() => {}}
        onRemove={() => {}}
        suggestions={suggestions}
        colors={colors}
      />,
    );
    expect(screen.getByText("SPY")).toBeInTheDocument();
    expect(screen.getByText("QQQ")).toBeInTheDocument();
  });

  it("opens the dropdown on focus and shows unselected suggestions", async () => {
    render(
      <BenchmarkCombobox
        selected={[ "SPY" ]}
        onAdd={() => {}}
        onRemove={() => {}}
        suggestions={suggestions}
        colors={colors}
      />,
    );
    await userEvent.setup().click(screen.getByPlaceholderText("Compare…"));
    // SPY is already selected so it shouldn't appear in the dropdown
    expect(screen.getByRole("button", { name: /QQQ.*NASDAQ-100/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /VTI.*Vanguard/ })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /^SPY.*S&P/ })).toBeNull();
  });

  it("filters by symbol substring (case-insensitive)", async () => {
    render(
      <BenchmarkCombobox
        selected={[]}
        onAdd={() => {}}
        onRemove={() => {}}
        suggestions={suggestions}
        colors={colors}
      />,
    );
    const input = screen.getByPlaceholderText("Compare…");
    await userEvent.setup().type(input, "qq");
    expect(screen.queryByRole("button", { name: /SPY/ })).toBeNull();
    expect(screen.getByRole("button", { name: /QQQ/ })).toBeInTheDocument();
  });

  it("offers an 'add ticker' custom option for an unknown symbol", async () => {
    render(
      <BenchmarkCombobox
        selected={[]}
        onAdd={() => {}}
        onRemove={() => {}}
        suggestions={suggestions}
        colors={colors}
      />,
    );
    await userEvent.setup().type(screen.getByPlaceholderText("Compare…"), "AAPL");
    expect(screen.getByText("add ticker")).toBeInTheDocument();
  });

  it("calls onAdd with the uppercase symbol when a row is clicked", async () => {
    const onAdd = vi.fn();
    render(
      <BenchmarkCombobox
        selected={[]}
        onAdd={onAdd}
        onRemove={() => {}}
        suggestions={suggestions}
        colors={colors}
      />,
    );
    const user = userEvent.setup();
    await user.click(screen.getByPlaceholderText("Compare…"));
    await user.click(screen.getByRole("button", { name: /QQQ/ }));
    expect(onAdd).toHaveBeenCalledWith("QQQ");
  });

  it("Enter adds the first option in the list", async () => {
    const onAdd = vi.fn();
    render(
      <BenchmarkCombobox
        selected={[]}
        onAdd={onAdd}
        onRemove={() => {}}
        suggestions={suggestions}
        colors={colors}
      />,
    );
    const user = userEvent.setup();
    const input = screen.getByPlaceholderText("Compare…");
    await user.click(input);
    await user.type(input, "QQ");
    fireEvent.keyDown(window, { key: "Enter" });
    expect(onAdd).toHaveBeenCalledWith("QQQ");
  });

  it("calls onRemove when the chip's X is clicked", async () => {
    const onRemove = vi.fn();
    render(
      <BenchmarkCombobox
        selected={[ "SPY" ]}
        onAdd={() => {}}
        onRemove={onRemove}
        suggestions={suggestions}
        colors={colors}
      />,
    );
    // The chip's button is the first one in the doc (the X next to SPY).
    await userEvent.setup().click(screen.getAllByRole("button")[0]);
    expect(onRemove).toHaveBeenCalledWith("SPY");
  });
});
