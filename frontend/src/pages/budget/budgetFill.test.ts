import { describe, it, expect } from "vitest";
import { budgetFillClass, isPacingOverrun } from "./budgetFill";

describe("budgetFillClass", () => {
  it("keeps the classic thresholds: red at 100, amber at 90", () => {
    expect(budgetFillClass(120)).toBe("bg-negative");
    expect(budgetFillClass(100)).toBe("bg-negative");
    expect(budgetFillClass(95)).toBe("bg-warning");
    expect(budgetFillClass(50)).toBe("bg-muted-foreground/60");
    expect(budgetFillClass(null)).toBe("bg-muted-foreground/60");
  });

  it("turns amber when spend outpaces the elapsed month", () => {
    // 60% used but only 40% of the month elapsed → projected overrun.
    expect(budgetFillClass(60, 40)).toBe("bg-warning");
    // Under pace stays neutral.
    expect(budgetFillClass(30, 40)).toBe("bg-muted-foreground/60");
  });

  it("ignores pace in the first tenth of the month and for closed months", () => {
    expect(budgetFillClass(50, 5)).toBe("bg-muted-foreground/60");
    expect(budgetFillClass(50, null)).toBe("bg-muted-foreground/60");
    expect(budgetFillClass(50)).toBe("bg-muted-foreground/60");
  });
});

describe("isPacingOverrun", () => {
  it("is true only for the pace-driven amber state", () => {
    expect(isPacingOverrun(60, 40)).toBe(true);
    expect(isPacingOverrun(95, 40)).toBe(false); // regular ≥90 amber
    expect(isPacingOverrun(30, 40)).toBe(false);
    expect(isPacingOverrun(60, null)).toBe(false);
  });
});
