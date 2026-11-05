import { describe, it, expect } from "vitest";
import { buildSpendBands, OTHER_ID } from "./spendBands";
import type { SpendBreakdown } from "@/api/types";

const NEUTRAL = "#898781";

const BREAKDOWN: SpendBreakdown = {
  series: [
    { id: "c1", name: "Groceries" },
    { id: "c2", name: "Dining" },
    { id: OTHER_ID, name: "Other" },
  ],
  months: {
    "2026-06-01": { c1: 600, c2: 300, other: 100 },
    "2026-07-01": { c1: 500, c2: 250, other: 250 },
  },
};

const COLORS = new Map([["Groceries", "#2a78d6"], ["Dining", "#1baf7a"]]);
const MONTHS = ["2026-06", "2026-07"];

describe("buildSpendBands", () => {
  it("keeps rank order, colors bands from the shared map, and puts Other last", () => {
    const { series } = buildSpendBands(BREAKDOWN, MONTHS, COLORS, NEUTRAL, "amount");

    expect(series).toEqual([
      { key: "c1", label: "Groceries", color: "#2a78d6" },
      { key: "c2", label: "Dining", color: "#1baf7a" },
      { key: OTHER_ID, label: "Other", color: NEUTRAL },
    ]);
  });

  it("emits one row per requested month, keyed by band id", () => {
    const { rows } = buildSpendBands(BREAKDOWN, MONTHS, COLORS, NEUTRAL, "amount");

    expect(rows).toEqual([
      { month: "2026-06", c1: 600, c2: 300, other: 100 },
      { month: "2026-07", c1: 500, c2: 250, other: 250 },
    ]);
  });

  it("zero-fills a month the payload has no data for, so the axis never shifts", () => {
    const { rows } = buildSpendBands(BREAKDOWN, ["2026-05", ...MONTHS], COLORS, NEUTRAL, "amount");

    expect(rows).toHaveLength(3);
    expect(rows[0]).toEqual({ month: "2026-05", other: 0 });
  });

  // A band with no palette slot left would render as a second gray fill
  // indistinguishable from Other, so its values move into Other instead.
  it("folds a band with no palette slot into Other, values and all", () => {
    const breakdown: SpendBreakdown = {
      series: [{ id: "c1", name: "Groceries" }, { id: "c9", name: "Coffee" }, { id: OTHER_ID, name: "Other" }],
      months: { "2026-06-01": { c1: 600, c9: 90, other: 10 } },
    };
    // "Coffee" fell past the 8 palette slots and resolved to the fallback.
    const colors = new Map([["Groceries", "#2a78d6"], ["Coffee", NEUTRAL]]);

    const { series, rows } = buildSpendBands(breakdown, ["2026-06"], colors, NEUTRAL, "amount");

    expect(series.map((s) => s.key)).toEqual(["c1", OTHER_ID]);
    expect(series.filter((s) => s.color === NEUTRAL)).toHaveLength(1);
    expect(rows[0]).toEqual({ month: "2026-06", c1: 600, other: 100 });
  });

  it("omits Other entirely when every band has its own slot", () => {
    const breakdown: SpendBreakdown = {
      series: [{ id: "c1", name: "Groceries" }],
      months: { "2026-06-01": { c1: 600 } },
    };

    const { series, rows } = buildSpendBands(breakdown, ["2026-06"], COLORS, NEUTRAL, "amount");

    expect(series.map((s) => s.key)).toEqual(["c1"]);
    expect(rows[0]).toEqual({ month: "2026-06", c1: 600 });
  });

  it("keeps negative amounts as-is, since stacked bars render below the baseline", () => {
    const breakdown: SpendBreakdown = {
      series: [{ id: "c1", name: "Groceries" }],
      months: { "2026-06-01": { c1: -40 } },
    };

    const { rows } = buildSpendBands(breakdown, ["2026-06"], COLORS, NEUTRAL, "amount");
    expect(rows[0].c1).toBe(-40);
  });

  it("floors negative amounts at zero in share mode, which can't normalize them", () => {
    const breakdown: SpendBreakdown = {
      series: [{ id: "c1", name: "Groceries" }, { id: "c2", name: "Dining" }, { id: OTHER_ID, name: "Other" }],
      months: { "2026-06-01": { c1: 600, c2: -40, other: -10 } },
    };

    const { rows } = buildSpendBands(breakdown, ["2026-06"], COLORS, NEUTRAL, "share");
    expect(rows[0]).toEqual({ month: "2026-06", c1: 600, c2: 0, other: 0 });
  });
});
