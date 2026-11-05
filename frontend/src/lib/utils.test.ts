import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { formatCurrency, formatDate, formatPercent, formatMonthLabel, fillLastMonths } from "./utils";

describe("formatCurrency", () => {
  it("formats a positive number", () => {
    expect(formatCurrency(1234.56)).toBe("$1,234.56");
  });

  it("formats a negative number", () => {
    expect(formatCurrency(-50)).toBe("-$50.00");
  });

  it("formats zero", () => {
    expect(formatCurrency(0)).toBe("$0.00");
  });

  it("returns — for null", () => {
    expect(formatCurrency(null)).toBe("—");
  });

  it("returns — for undefined", () => {
    expect(formatCurrency(undefined)).toBe("—");
  });

  it("uses compact notation", () => {
    expect(formatCurrency(1_500_000, true)).toBe("$1.5M");
    expect(formatCurrency(2_300, true)).toBe("$2.3K");
  });
});

describe("formatPercent", () => {
  it("formats a positive value with + prefix", () => {
    expect(formatPercent(12.5)).toBe("+12.5%");
  });

  it("formats a negative value", () => {
    expect(formatPercent(-3.2)).toBe("-3.2%");
  });

  it("returns — for null", () => {
    expect(formatPercent(null)).toBe("—");
  });
});

describe("formatDate", () => {
  it("formats a full ISO datetime string", () => {
    expect(formatDate("2026-05-12T12:00:00")).toBe("May 12, 2026");
  });

  it("formats a plain yyyy-mm-dd string as a local date (no UTC rollback)", () => {
    expect(formatDate("2026-06-15")).toBe("Jun 15, 2026");
  });

  it("returns — for null", () => {
    expect(formatDate(null)).toBe("—");
  });

  it("returns — for empty string", () => {
    expect(formatDate("")).toBe("—");
  });
});

describe("formatMonthLabel", () => {
  it("formats a yyyy-mm key as abbreviated month", () => {
    expect(formatMonthLabel("2026-01")).toBe("Jan");
    expect(formatMonthLabel("2026-12")).toBe("Dec");
  });

  it("handles yyyy-mm-dd keys (slices to yyyy-mm)", () => {
    expect(formatMonthLabel("2026-06-15")).toBe("Jun");
  });
});

describe("fillLastMonths", () => {
  beforeEach(() => {
    // Pin date to 2026-05-12
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-05-12"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns exactly n months ending with the current month", () => {
    const result = fillLastMonths({}, 6);
    expect(result).toHaveLength(6);
    expect(result[5].month).toBe("2026-05");
    expect(result[0].month).toBe("2025-12");
  });

  it("defaults to 24 months", () => {
    const result = fillLastMonths({});
    expect(result).toHaveLength(24);
    expect(result[23].month).toBe("2026-05");
    expect(result[0].month).toBe("2024-06");
  });

  it("fills matching months from data", () => {
    const data = { "2026-03": 100, "2026-05": 250 };
    const result = fillLastMonths(data, 6);
    const mar = result.find((d) => d.month === "2026-03");
    const may = result.find((d) => d.month === "2026-05");
    const apr = result.find((d) => d.month === "2026-04");
    expect(mar?.amount).toBe(100);
    expect(may?.amount).toBe(250);
    expect(apr?.amount).toBe(0);
  });

  it("fills zero for months with no data", () => {
    const result = fillLastMonths({}, 3);
    expect(result.every((d) => d.amount === 0)).toBe(true);
  });

  it("normalises long-form timestamp keys (e.g. from Groupdate)", () => {
    const data = { "2026-04-01 00:00:00 UTC": 500 };
    const result = fillLastMonths(data, 6);
    const apr = result.find((d) => d.month === "2026-04");
    expect(apr?.amount).toBe(500);
  });
});
