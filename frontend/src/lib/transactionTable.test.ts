import { describe, it, expect } from "vitest";
import {
  applyFilters,
  applyTransferVisibility,
  rowGroupKey,
  searchTransactions,
  sortGroupKey,
  sortTransactions,
} from "./transactionTable";
import type { ActiveFilter } from "@/components/FilterBar";
import type { CashTransaction } from "@/api/types";

function txn(overrides: Partial<CashTransaction> = {}): CashTransaction {
  return {
    id: Math.random().toString(36).slice(2),
    source: "bank",
    transaction_date: "2026-03-15",
    post_date: null,
    description: "GROCERY RUN",
    amount: -25.5,
    transaction_type: "Debit",
    category_id: "cat-1",
    category_name: "Groceries",
    category_parent_name: null,
    merchant_id: "mer-1",
    merchant_name: "Safeway",
    account_id: "acc-1",
    account_name: "Checking",
    balance: null,
    memo: null,
    transfer_id: null,
    transfer_kind: null,
    transfer_include_in_spend: null,
    loan_id: null,
    loan_name: null,
    tags: [],
    created_at: "2026-03-15T00:00:00Z",
    updated_at: "2026-03-15T00:00:00Z",
    ...overrides,
  } as CashTransaction;
}

const f = (field: string, operator: string, value = ""): ActiveFilter =>
  ({ field, operator, value }) as ActiveFilter;

describe("applyFilters", () => {
  it("returns everything when no filters are active", () => {
    const rows = [txn(), txn()];
    expect(applyFilters(rows, [], true)).toBe(rows);
  });

  it("matches blank and present on nullable ids", () => {
    const withMerchant = txn({ merchant_id: "mer-1" });
    const without = txn({ merchant_id: null });
    const rows = [withMerchant, without];

    expect(applyFilters(rows, [f("merchant_id", "blank")], true)).toEqual([without]);
    expect(applyFilters(rows, [f("merchant_id", "present")], true)).toEqual([withMerchant]);
  });

  it("matches merchant_name contains case-insensitively", () => {
    const rows = [txn({ merchant_name: "Safeway" }), txn({ merchant_name: "Costco" })];
    expect(applyFilters(rows, [f("merchant_name", "contains", "SAFE")], true)).toHaveLength(1);
  });

  it("compares amounts on absolute value, so sign never flips the operator", () => {
    const rows = [txn({ amount: -100 }), txn({ amount: -10 })];
    expect(applyFilters(rows, [f("amount", "greater_than", "50")], true)).toEqual([rows[0]]);
    expect(applyFilters(rows, [f("amount", "less_than", "50")], true)).toEqual([rows[1]]);
  });

  it("matches a month prefix on transaction_date", () => {
    const rows = [txn({ transaction_date: "2026-03-01" }), txn({ transaction_date: "2026-04-01" })];
    expect(applyFilters(rows, [f("transaction_date", "month", "2026-03")], true)).toEqual([rows[0]]);
  });

  it("honours date range operators", () => {
    const rows = [
      txn({ transaction_date: "2026-01-01" }),
      txn({ transaction_date: "2026-06-01" }),
    ];
    expect(applyFilters(rows, [f("transaction_date", "gte", "2026-03-01")], true)).toEqual([rows[1]]);
    expect(applyFilters(rows, [f("transaction_date", "lte", "2026-03-01")], true)).toEqual([rows[0]]);
  });

  it("ANDs filters when matchAll, ORs them otherwise", () => {
    // Safeway matches both filters; Costco matches only the amount one, so
    // AND keeps just Safeway while OR keeps both.
    const rows = [
      txn({ merchant_name: "Safeway", amount: -100 }),
      txn({ merchant_name: "Costco", amount: -100 }),
    ];
    const filters = [f("merchant_name", "contains", "safe"), f("amount", "greater_than", "50")];

    expect(applyFilters(rows, filters, true)).toEqual([rows[0]]);
    expect(applyFilters(rows, filters, false)).toEqual(rows);
  });
});

describe("applyTransferVisibility", () => {
  it("passes everything through when transfers are shown", () => {
    const rows = [txn({ transfer_id: "t1" }), txn()];
    expect(applyTransferVisibility(rows, true)).toBe(rows);
  });

  // A counted payment leg is part of spend; hiding it would hide real money.
  it("keeps counted outflow payment legs even when transfers are hidden", () => {
    const plain = txn({ transfer_id: null });
    const counted = txn({ transfer_id: "t1", transfer_include_in_spend: true, amount: -50 });
    const uncounted = txn({ transfer_id: "t2", transfer_include_in_spend: false, amount: -50 });
    const countedInflow = txn({ transfer_id: "t3", transfer_include_in_spend: true, amount: 50 });

    expect(applyTransferVisibility([plain, counted, uncounted, countedInflow], false))
      .toEqual([plain, counted]);
  });
});

describe("sortTransactions", () => {
  const base = { secondarySort: null, groupBy: "none" as const };

  it("sorts by date in both directions", () => {
    const older = txn({ transaction_date: "2026-01-01" });
    const newer = txn({ transaction_date: "2026-05-01" });

    expect(sortTransactions([older, newer], { ...base, primarySort: { field: "date", dir: "desc" } }))
      .toEqual([newer, older]);
    expect(sortTransactions([newer, older], { ...base, primarySort: { field: "date", dir: "asc" } }))
      .toEqual([older, newer]);
  });

  it("does not mutate its input", () => {
    const rows = [txn({ transaction_date: "2026-01-01" }), txn({ transaction_date: "2026-05-01" })];
    const snapshot = [...rows];
    sortTransactions(rows, { ...base, primarySort: { field: "date", dir: "desc" } });
    expect(rows).toEqual(snapshot);
  });

  it("breaks ties with the secondary sort", () => {
    const cheap = txn({ transaction_date: "2026-01-01", amount: -5 });
    const dear = txn({ transaction_date: "2026-01-01", amount: -500 });

    expect(sortTransactions([cheap, dear], {
      groupBy: "none",
      primarySort: { field: "date", dir: "desc" },
      secondarySort: { field: "amount", dir: "asc" },
    })).toEqual([dear, cheap]);
  });

  // Groups lead, so rows never interleave across months; and a descending
  // date sort must put the newest month first rather than the oldest.
  it("orders month groups to follow the date sort direction", () => {
    const jan = txn({ transaction_date: "2026-01-10" });
    const mar = txn({ transaction_date: "2026-03-10" });

    expect(sortTransactions([jan, mar], {
      groupBy: "month", secondarySort: null, primarySort: { field: "date", dir: "desc" },
    })).toEqual([mar, jan]);

    expect(sortTransactions([mar, jan], {
      groupBy: "month", secondarySort: null, primarySort: { field: "date", dir: "asc" },
    })).toEqual([jan, mar]);
  });

  it("keeps rows of one merchant group together regardless of date", () => {
    const rows = [
      txn({ merchant_name: "Zoo", transaction_date: "2026-05-01" }),
      txn({ merchant_name: "Acme", transaction_date: "2026-04-01" }),
      txn({ merchant_name: "Zoo", transaction_date: "2026-03-01" }),
    ];
    const out = sortTransactions(rows, {
      groupBy: "merchant", secondarySort: null, primarySort: { field: "date", dir: "desc" },
    });
    expect(out.map((t) => t.merchant_name)).toEqual(["Acme", "Zoo", "Zoo"]);
  });
});

describe("group keys", () => {
  it("sorts blank merchants last but labels them readably", () => {
    const blank = txn({ merchant_name: null, category_name: null });
    expect(sortGroupKey(blank, "merchant")).toBe("￿");
    expect(rowGroupKey(blank, "merchant")).toBe("No merchant");
    expect(rowGroupKey(blank, "category")).toBe("Uncategorized");
  });

  it("keeps same-named subcategories of different parents apart", () => {
    const carGas  = txn({ category_name: "Gas", category_parent_name: "Car" });
    const homeGas = txn({ category_name: "Gas", category_parent_name: "Home" });
    expect(rowGroupKey(carGas, "category")).toBe("Car › Gas");
    expect(rowGroupKey(homeGas, "category")).toBe("Home › Gas");
    expect(sortGroupKey(carGas, "category")).not.toBe(sortGroupKey(homeGas, "category"));
    expect(rowGroupKey(txn({ category_name: "Dining Out" }), "category")).toBe("Dining Out");
  });

  it("keys months by YYYY-MM", () => {
    expect(rowGroupKey(txn({ transaction_date: "2026-03-15" }), "month")).toBe("2026-03");
  });
});

describe("searchTransactions", () => {
  it("returns the same array reference for a blank query", () => {
    const rows = [txn()];
    expect(searchTransactions(rows, "   ")).toBe(rows);
  });

  it("requires every term to match, across fields", () => {
    const rows = [
      txn({ description: "COFFEE BAR", merchant_name: "Blue Bottle", category_name: "Dining" }),
      txn({ description: "COFFEE BEANS", merchant_name: "Costco", category_name: "Groceries" }),
    ];
    expect(searchTransactions(rows, "coffee blue")).toEqual([rows[0]]);
    expect(searchTransactions(rows, "coffee")).toHaveLength(2);
    expect(searchTransactions(rows, "coffee nothing")).toEqual([]);
  });

  it("searches the absolute amount as text", () => {
    const rows = [txn({ amount: -42.75 }), txn({ amount: -1 })];
    expect(searchTransactions(rows, "42.75")).toEqual([rows[0]]);
  });

  it("preserves input order so a pre-sorted array stays sorted", () => {
    const rows = [
      txn({ description: "A COFFEE", transaction_date: "2026-05-01" }),
      txn({ description: "B COFFEE", transaction_date: "2026-01-01" }),
    ];
    expect(searchTransactions(rows, "coffee")).toEqual(rows);
  });
});
