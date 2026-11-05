import { describe, it, expect } from "vitest";
import { monthDateRange, transactionsHref } from "./links";

describe("monthDateRange", () => {
  it("expands a month to its first and last day", () => {
    expect(monthDateRange("2026-02")).toEqual({ from: "2026-02-01", to: "2026-02-28" });
    expect(monthDateRange("2024-02")).toEqual({ from: "2024-02-01", to: "2024-02-29" });
    expect(monthDateRange("2026-12")).toEqual({ from: "2026-12-01", to: "2026-12-31" });
  });
});

describe("transactionsHref", () => {
  it("returns the bare path with no params", () => {
    expect(transactionsHref({})).toBe("/transactions");
  });

  it("expands month into start/end dates", () => {
    expect(transactionsHref({ month: "2026-03" })).toBe(
      "/transactions?start_date=2026-03-01&end_date=2026-03-31",
    );
  });

  it("month wins over explicit from/to", () => {
    expect(transactionsHref({ month: "2026-03", from: "2020-01-01", to: "2020-12-31" })).toBe(
      "/transactions?start_date=2026-03-01&end_date=2026-03-31",
    );
  });

  it("maps every entity filter to its query param", () => {
    expect(transactionsHref({
      from: "2026-01-01", to: "2026-07-03",
      categoryId: "c1", merchantId: "m1", tagId: "t1", accountId: "a1", source: "credit_card",
    })).toBe(
      "/transactions?start_date=2026-01-01&end_date=2026-07-03&category_id=c1&merchant_id=m1&tag_id=t1&account_id=a1&source=credit_card",
    );
  });
});
