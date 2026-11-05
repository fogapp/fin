import { describe, it, expect } from "vitest";
import { formatStatValue, statYFormat, invertColorFor, mtdVsProratedPrior } from "./statFormat";

describe("formatStatValue", () => {
  it("formats currency", () => {
    expect(formatStatValue(4321.1, "currency")).toBe("$4,321.10");
    expect(formatStatValue(1234567, "currency", { compact: true })).toBe("$1.2M");
  });

  it("formats counts without decimals for integers, one decimal otherwise", () => {
    expect(formatStatValue(1234, "count")).toBe("1,234");
    expect(formatStatValue(104.33, "count")).toBe("104.3");
    expect(formatStatValue(1234, "count", { compact: true })).toBe("1.2K");
  });

  it("formats percent unsigned with one decimal", () => {
    expect(formatStatValue(23.44, "percent")).toBe("23.4%");
    expect(formatStatValue(-12.5, "percent")).toBe("-12.5%");
  });

  it("renders the standard null placeholder", () => {
    expect(formatStatValue(null, "currency")).toBe("—");
    expect(formatStatValue(undefined, "count")).toBe("—");
  });
});

describe("statYFormat", () => {
  it("produces compact axis ticks", () => {
    expect(statYFormat("currency")(1200)).toBe("$1.2K");
    expect(statYFormat("count")(1200)).toBe("1.2K");
    expect(statYFormat("percent")(12)).toBe("12.0%");
  });
});

describe("invertColorFor", () => {
  it("inverts only for down_good", () => {
    expect(invertColorFor("down_good")).toBe(true);
    expect(invertColorFor("up_good")).toBe(false);
    expect(invertColorFor("neutral")).toBe(false);
  });
});

describe("mtdVsProratedPrior", () => {
  // Sept 10 of a 30-day month: a third of August counts as the comparison.
  const today = new Date(2026, 8, 10);

  it("compares month-to-date spend with the prior month prorated to today", () => {
    const { mtd, change } = mtdVsProratedPrior(
      [{ month: "2026-08", amount: 900 }, { month: "2026-09", amount: 400 }],
      today,
    );
    expect(mtd).toBe(400);
    expect(change).toBeCloseTo(((400 - 300) / 300) * 100);
  });

  it("returns a null change when there was no prior spend", () => {
    expect(mtdVsProratedPrior([{ month: "2026-09", amount: 50 }], today)).toEqual({ mtd: 50, change: null });
  });

  it("reads zero MTD spend when the current month is missing", () => {
    expect(mtdVsProratedPrior([{ month: "2026-08", amount: 900 }], today)).toEqual({ mtd: 0, change: -100 });
  });

  it("rolls back across a year boundary", () => {
    const jan = new Date(2027, 0, 31);
    expect(mtdVsProratedPrior([{ month: "2026-12", amount: 100 }, { month: "2027-01", amount: 100 }], jan).change).toBe(0);
  });
});
