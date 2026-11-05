import { describe, it, expect } from "vitest";
import type { CashTransaction, TransactionContext } from "@/api/types";
import { categorySuggestion, historyHeadline, insights, relativeDays, roughRhythm, spendReason, uncategorizedPeers } from "./insights";

const TX = {
  id: "t", amount: -30, transaction_type: "Sale", transfer_id: null, budget_excluded: false, category_id: "c1",
} as CashTransaction;

const stats = (over: Partial<NonNullable<TransactionContext["stats"]>> = {}) => ({
  count: 6, ordinal: 6, median: 12, p25: 10, p75: 14, min: 9, max: 30, percentile: 1,
  ratio_to_median: 2.5, first_date: "2026-01-01", last_date: "2026-06-01",
  trailing_year_total: 90, trailing_year_count: 6, ...over,
});

const ctx = (over: Partial<TransactionContext> = {}): TransactionContext => ({
  history: { basis: "merchant", label: "Netflix", total: 6, rows: [] },
  stats: stats(),
  cadence: null, series: null,
  treatment: { spend: true, income: false, budget: true, merchant_excluded: false },
  budget: null, duplicates: [], related: [], same_day: { total: 0, rows: [] }, suggested_category: null,
  ...over,
});

describe("historyHeadline", () => {
  it("calls out an outlier against the median", () => {
    expect(historyHeadline(TX, ctx())).toBe("Charge 6 of 6 at Netflix — 2.5× the usual $12.00.");
  });

  it("calls a typical amount typical", () => {
    expect(historyHeadline({ ...TX, amount: -12 }, ctx({ stats: stats({ ratio_to_median: 1, max: 14 }) })))
      .toBe("Charge 6 of 6 at Netflix — right around the usual $12.00.");
  });

  it("doesn't judge with fewer than three peers", () => {
    expect(historyHeadline(TX, ctx({ stats: stats({ count: 2, ordinal: 2 }) }))).toBe("Charge 2 of 2 at Netflix.");
  });

  it("names a first charge", () => {
    expect(historyHeadline(TX, ctx({ stats: null }))).toBe("The first charge at Netflix.");
  });
});

describe("insights", () => {
  it("flags an unusual amount, a duplicate and a full refund", () => {
    const keys = insights(TX, ctx({
      duplicates: [{ id: "d", transaction_date: "2026-06-02", description: null, amount: -30, account_name: null, merchant_name: null, category_id: null, category_name: null, transfer_id: null, date_diff: 1 }],
      related: [{ id: "r", transaction_date: "2026-06-09", description: null, amount: 30, account_name: null, merchant_name: null, category_id: null, category_name: null, transfer_id: null, date_diff: 8 }],
    })).map((i) => i.key);
    expect(keys).toEqual(["amount", "duplicate", "refund"]);
  });

  it("prefers a tracked series over a detected cadence", () => {
    const out = insights(TX, ctx({
      series: { id: "s", name: "Netflix", status: "active", kind: "subscription", cadence_description: "Monthly", next_expected_date: null, average_amount: 12, annual_equivalent: 144, includes_transaction: true },
      cadence: { granularity: "month", quantity: 1, anchor: {}, description: "Monthly", confidence: 1, hit_rate: 1, matched_count: 6, missed_count: 0, includes_transaction: true, average_amount: 12, next_expected_date: "2026-07-01", matched_ids: [] },
    }));
    expect(out.find((i) => i.key === "series")?.label).toBe("Monthly subscription");
    expect(out.some((i) => i.key === "cadence")).toBe(false);
  });

  it("notes when this charge tipped the budget over", () => {
    const budget = { scope: "line" as const, category_id: "c1", category_name: "Fun", period: "monthly" as const, month: "2026-06", available: 100, actual: 110, before: 80, contribution: 30, remaining: -10, typical: null, history: [] };
    expect(insights(TX, ctx({ budget })).some((i) => i.key === "over")).toBe(true);
    expect(insights(TX, ctx({ budget: { ...budget, before: 105 } })).some((i) => i.key === "over")).toBe(false);
  });
});

describe("decisions", () => {
  it("suggests a category only when most peers agree", () => {
    expect(categorySuggestion(ctx({ suggested_category: { category_id: "c2", category_name: "Fun", count: 4, of: 5 } }))).not.toBeNull();
    expect(categorySuggestion(ctx({ suggested_category: { category_id: "c2", category_name: "Fun", count: 2, of: 5 } }))).toBeNull();
  });

  it("offers uncategorized peers, never this row or transfer legs", () => {
    const rows = [
      { id: "t", category_id: "c1", transfer_id: null },
      { id: "a", category_id: null, transfer_id: null },
      { id: "b", category_id: null, transfer_id: "x" },
      { id: "c", category_id: "c9", transfer_id: null },
    ].map((r) => ({ ...r, transaction_date: "2026-01-01", description: null, amount: -1, account_name: null, merchant_name: null, category_name: null }));
    expect(uncategorizedPeers(TX, ctx({ history: { basis: "merchant", label: "N", total: 4, rows } }))).toEqual(["a"]);
  });

  it("explains why a row isn't spending", () => {
    const off = { spend: false, income: false, budget: false, merchant_excluded: false };
    expect(spendReason({ ...TX, transfer_id: "x" }, ctx({ treatment: off }))).toMatch(/between your accounts/);
    expect(spendReason(TX, ctx({ treatment: { ...off, merchant_excluded: true } }))).toMatch(/merchant is excluded/);
  });

  it("phrases day offsets", () => {
    expect(relativeDays(0)).toBe("the same day");
    expect(relativeDays(1)).toBe("1 day later");
    expect(relativeDays(-3)).toBe("3 days earlier");
  });
});

describe("roughRhythm", () => {
  const rows = (dates: string[]) => dates.map((d, i) => ({
    id: `r${i}`, transaction_date: d, description: null, amount: -11, account_name: null,
    merchant_name: null, category_id: null, category_name: null, transfer_id: null,
  }));
  const flat = stats({ count: 5, median: 11, p25: 11, p75: 11, ratio_to_median: 1 });

  it("reads one same-price charge per consecutive month as monthly, whatever the day", () => {
    const c = ctx({ stats: flat, history: { basis: "merchant", label: "Spotify", total: 5, rows: rows(["2026-01-03", "2026-02-27", "2026-03-11", "2026-04-02", "2026-05-19"]) } });
    expect(roughRhythm(c)?.cadenceKey).toBe("month-1");
  });

  it("ignores a frequent habit and a price that moves", () => {
    const habit = ctx({ stats: flat, history: { basis: "merchant", label: "Cafe", total: 5, rows: rows(["2026-01-03", "2026-01-04", "2026-01-09", "2026-01-21", "2026-02-02"]) } });
    expect(roughRhythm(habit)).toBeNull();
    const varied = ctx({ stats: stats({ median: 11, p25: 6, p75: 20 }), history: { basis: "merchant", label: "X", total: 5, rows: rows(["2026-01-03", "2026-02-03", "2026-03-03", "2026-04-03", "2026-05-03"]) } });
    expect(roughRhythm(varied)).toBeNull();
  });
});
