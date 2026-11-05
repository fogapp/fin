import { describe, expect, it } from "vitest";
import type { BudgetLine } from "@/api/types";
import { groupLines, orderedLines } from "./budgetGroups";

function line(overrides: Partial<BudgetLine>): BudgetLine {
  return {
    id: "l", category_id: "c", category_name: "C", parent_id: null, parent_name: null,
    period: "monthly", mode: "ongoing", set_in: "2026-01", planned: 0, rollover: false, rollover_amount: 0,
    actual: 0, month_actual: 0, remaining: 0, percent_used: 0, typical: 0, projected: null, rolled_up_children: [],
    ...overrides,
  };
}

describe("groupLines", () => {
  it("nests subcategories under their parent and sorts groups by planned", () => {
    const groups = groupLines([
      line({ category_id: "food", category_name: "Food", planned: 500 }),
      line({ category_id: "coffee", category_name: "Coffee", parent_id: "food", parent_name: "Food", planned: 60 }),
      line({ category_id: "home", category_name: "Home", planned: 3000 }),
      line({ category_id: "nanny", category_name: "Nanny", parent_id: "kids", parent_name: "Children", planned: 900 }),
    ]);

    expect(groups.map((g) => g.name)).toEqual(["Home", "Children", "Food"]);
    expect(groups[1].line).toBeNull();
    expect(groups[2].planned).toBe(560);
    expect(groups[2].children.map((c) => c.category_name)).toEqual(["Coffee"]);
  });

  it("orders lines parent-first within each group", () => {
    const ordered = orderedLines([
      line({ category_id: "coffee", category_name: "Coffee", parent_id: "food", parent_name: "Food", planned: 60 }),
      line({ category_id: "food", category_name: "Food", planned: 500 }),
    ]);
    expect(ordered.map((l) => l.category_name)).toEqual(["Food", "Coffee"]);
  });
});
