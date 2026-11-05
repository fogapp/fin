import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { builtinOption, timeframeRange, useTimeframe, type TimeframeOption } from "./timeframe";
import { TimeframeSelector } from "./TimeframeSelector";

describe("timeframeRange", () => {
  const today = new Date(2026, 6, 3); // 2026-07-03 (local)

  it("maps 3M / 6M / 1Y / YTD to {from, to} ISO dates ending today", () => {
    expect(timeframeRange("3m", today)).toEqual({ from: "2026-04-03", to: "2026-07-03" });
    expect(timeframeRange("6m", today)).toEqual({ from: "2026-01-03", to: "2026-07-03" });
    expect(timeframeRange("1y", today)).toEqual({ from: "2025-07-03", to: "2026-07-03" });
    expect(timeframeRange("ytd", today)).toEqual({ from: "2026-01-01", to: "2026-07-03" });
  });

  it("All omits both bounds (backend default window)", () => {
    expect(timeframeRange("all", today)).toEqual({});
  });

  it("maps the calendar presets to whole periods", () => {
    expect(timeframeRange("mtd", today)).toEqual({ from: "2026-07-01", to: "2026-07-03" });
    expect(timeframeRange("last_month", today)).toEqual({ from: "2026-06-01", to: "2026-06-30" });
    expect(timeframeRange("qtd", today)).toEqual({ from: "2026-07-01", to: "2026-07-03" });
    expect(timeframeRange("last_quarter", today)).toEqual({ from: "2026-04-01", to: "2026-06-30" });
    expect(timeframeRange("last_year", today)).toEqual({ from: "2025-01-01", to: "2025-12-31" });
  });

  it("rolls last month / last quarter back across the year boundary", () => {
    const jan = new Date(2026, 0, 15);
    expect(timeframeRange("last_month", jan)).toEqual({ from: "2025-12-01", to: "2025-12-31" });
    expect(timeframeRange("last_quarter", jan)).toEqual({ from: "2025-10-01", to: "2025-12-31" });
    // Leap-year February ends on the 29th.
    expect(timeframeRange("last_month", new Date(2028, 2, 10))).toEqual({ from: "2028-02-01", to: "2028-02-29" });
  });
});

describe("builtinOption", () => {
  it("labels ended calendar periods with the period itself", () => {
    const today = new Date(2026, 0, 15);
    expect(builtinOption("last_month", today).label).toBe("Dec");
    expect(builtinOption("last_quarter", today).label).toBe("Q4");
    expect(builtinOption("last_year", today).label).toBe("2025");
    expect(builtinOption("mtd", today)).toMatchObject({ label: "MTD", description: "Month to date" });
  });
});

function Harness({ storageKey, options, defaultPreset = "1y" }: {
  storageKey?: string;
  options?: TimeframeOption[];
  defaultPreset?: string;
}) {
  const timeframe = useTimeframe({ defaultPreset, storageKey, options });
  return (
    <div>
      <TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />
      <output data-testid="range">{timeframe.from ?? "∅"}|{timeframe.to ?? "∅"}</output>
      <output data-testid="description">{timeframe.description}</output>
    </div>
  );
}

describe("TimeframeSelector + useTimeframe", () => {
  beforeEach(() => {
    sessionStorage.clear();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(2026, 6, 3, 12));
  });
  afterEach(() => vi.useRealTimers());

  it("renders the preset row with the selection marked", () => {
    render(<Harness />);
    for (const label of ["3M", "6M", "1Y", "YTD", "All"]) {
      expect(screen.getByRole("button", { name: label })).toBeInTheDocument();
    }
    expect(screen.getByRole("button", { name: "1Y" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "3M" })).toHaveAttribute("aria-pressed", "false");
  });

  it("changing the preset emits the matching from/to", () => {
    render(<Harness />);
    expect(screen.getByTestId("range")).toHaveTextContent("2025-07-03|2026-07-03");

    fireEvent.click(screen.getByRole("button", { name: "3M" }));
    expect(screen.getByTestId("range")).toHaveTextContent("2026-04-03|2026-07-03");
    expect(screen.getByRole("button", { name: "3M" })).toHaveAttribute("aria-pressed", "true");

    fireEvent.click(screen.getByRole("button", { name: "All" }));
    expect(screen.getByTestId("range")).toHaveTextContent("∅|∅");
  });

  it("persists the preset under the storage key", () => {
    const { unmount } = render(<Harness storageKey="tf-test" />);
    fireEvent.click(screen.getByRole("button", { name: "YTD" }));
    expect(sessionStorage.getItem("tf-test")).toBe("ytd");
    unmount();

    render(<Harness storageKey="tf-test" />);
    expect(screen.getByRole("button", { name: "YTD" })).toHaveAttribute("aria-pressed", "true");
  });

  it("offers only the requested preset subset", () => {
    render(<TimeframeSelector value="1y" onChange={() => {}} presets={["3m", "ytd", "1y", "all"]} />);
    expect(screen.queryByRole("button", { name: "6M" })).toBeNull();
    expect(screen.getByRole("button", { name: "All" })).toBeInTheDocument();
  });

  it("shows the presets in catalog order regardless of the order requested", () => {
    render(<TimeframeSelector value="1y" onChange={() => {}} presets={["all", "3m", "1y"]} />);
    const labels = screen.getAllByRole("button").map((b) => b.textContent);
    expect(labels).toEqual(["3M", "1Y", "All"]);
  });
});

describe("useTimeframe with configured options", () => {
  const LAST_2Y: TimeframeOption = { key: "c_2y", label: "2Y", description: "Last 2 years", from: "2024-07-03", to: "2026-07-03" };

  beforeEach(() => {
    sessionStorage.clear();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(2026, 6, 3, 12));
  });
  afterEach(() => vi.useRealTimers());

  it("renders the given options and starts on the default key", () => {
    render(<Harness options={[builtinOption("mtd"), LAST_2Y]} defaultPreset="c_2y" />);
    expect(screen.getByRole("button", { name: "2Y" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.queryByRole("button", { name: "1Y" })).toBeNull();
    expect(screen.getByTestId("range")).toHaveTextContent("2024-07-03|2026-07-03");
    expect(screen.getByTestId("description")).toHaveTextContent("Last 2 years");
  });

  it("falls back to the default when the stored selection isn't offered, without forgetting it", () => {
    sessionStorage.setItem("tf-test", "c_2y");
    const { rerender } = render(<Harness storageKey="tf-test" options={[builtinOption("mtd")]} defaultPreset="mtd" />);
    expect(screen.getByTestId("range")).toHaveTextContent("2026-07-01|2026-07-03");

    // Options arrive (preferences finished loading) — the stored pick resolves.
    rerender(<Harness storageKey="tf-test" options={[builtinOption("mtd"), LAST_2Y]} defaultPreset="mtd" />);
    expect(screen.getByRole("button", { name: "2Y" })).toHaveAttribute("aria-pressed", "true");
    expect(sessionStorage.getItem("tf-test")).toBe("c_2y");
  });

  it("falls back to the first option when the default key isn't offered either", () => {
    render(<Harness options={[builtinOption("mtd"), LAST_2Y]} defaultPreset="1y" />);
    expect(screen.getByRole("button", { name: "MTD" })).toHaveAttribute("aria-pressed", "true");
  });

  it("describes a custom range as such", () => {
    render(<Harness storageKey="tf-test" />);
    fireEvent.click(screen.getByRole("button", { name: "Custom" }));
    fireEvent.change(screen.getByLabelText("From"), { target: { value: "2026-01-01" } });
    fireEvent.change(screen.getByLabelText("To"), { target: { value: "2026-02-01" } });
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));
    expect(screen.getByTestId("range")).toHaveTextContent("2026-01-01|2026-02-01");
    expect(screen.getByTestId("description")).toHaveTextContent("Custom range");
  });
});
