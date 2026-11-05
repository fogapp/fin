import { describe, it, expect, vi } from "vitest";
import { QueryClient } from "@tanstack/react-query";
import {
  updateTransactionInCaches,
  invalidateTransactionAggregates,
  refreshTransactionsAfterWorkflowApply,
  WORKFLOW_APPLY_REFRESH_DELAY_MS,
} from "./transactionCache";
import type { CashTransaction } from "@/api/types";

function tx(overrides: Partial<CashTransaction>): CashTransaction {
  return {
    id: "t1",
    transaction_date: "2026-01-01",
    description: "X",
    amount: -10,
    source: "credit_card",
    transaction_type: "Sale",
    tags: [],
    ...overrides,
  } as CashTransaction;
}

describe("updateTransactionInCaches", () => {
  it("replaces the row by id in flat lists, paged lists, previews and the detail entry", () => {
    const qc = new QueryClient();
    const a = tx({ id: "t1", memo: null });
    const b = tx({ id: "t2" });

    qc.setQueryData(["cash_transactions", {}], [a, b]);
    qc.setQueryData(["cash_transactions", "paged", {}], [a]);
    qc.setQueryData(["cash_transactions", "match_preview", []], { transactions: [a], total: 1 });
    qc.setQueryData(["cash_transactions", "t1"], a);

    const updated = tx({ id: "t1", memo: "hello" });
    updateTransactionInCaches(qc, updated);

    expect(qc.getQueryData(["cash_transactions", {}])).toEqual([updated, b]);
    expect(qc.getQueryData(["cash_transactions", "paged", {}])).toEqual([updated]);
    expect(qc.getQueryData(["cash_transactions", "match_preview", []])).toEqual({
      transactions: [updated],
      total: 1,
    });
    expect(qc.getQueryData(["cash_transactions", "t1"])).toEqual(updated);
  });

  it("leaves unrelated rows and other detail entries untouched", () => {
    const qc = new QueryClient();
    const other = tx({ id: "t2", memo: "keep me" });
    qc.setQueryData(["cash_transactions", "t2"], other);
    qc.setQueryData(["cash_transactions", {}], [other]);

    updateTransactionInCaches(qc, tx({ id: "t1", memo: "new" }));

    expect(qc.getQueryData(["cash_transactions", "t2"])).toEqual(other);
    expect(qc.getQueryData(["cash_transactions", {}])).toEqual([other]);
  });

  it("falls back to prefix invalidation when the response is not a row", () => {
    const qc = new QueryClient();
    const invalidateSpy = vi.spyOn(qc, "invalidateQueries");
    updateTransactionInCaches(qc, undefined);
    expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: ["cash_transactions"] });
  });
});

describe("invalidateTransactionAggregates", () => {
  it("invalidates the derived aggregate prefixes but not the transaction lists", () => {
    const qc = new QueryClient();
    const invalidateSpy = vi.spyOn(qc, "invalidateQueries");
    invalidateTransactionAggregates(qc);
    const keys = invalidateSpy.mock.calls.map(([f]) => (f as { queryKey: unknown[] }).queryKey[0]);
    expect(keys).toContain("dashboard");
    expect(keys).toContain("cashflow");
    expect(keys).toContain("budget");
    expect(keys).not.toContain("cash_transactions");
  });
});

describe("refreshTransactionsAfterWorkflowApply", () => {
  it("refetches transactions and aggregates only after the delay", () => {
    vi.useFakeTimers();
    try {
      const qc = new QueryClient();
      const invalidateSpy = vi.spyOn(qc, "invalidateQueries");
      refreshTransactionsAfterWorkflowApply(qc);
      expect(invalidateSpy).not.toHaveBeenCalled();

      vi.advanceTimersByTime(WORKFLOW_APPLY_REFRESH_DELAY_MS);
      const keys = invalidateSpy.mock.calls.map(([f]) => (f as { queryKey: unknown[] }).queryKey[0]);
      expect(keys).toContain("cash_transactions");
      expect(keys).toContain("dashboard");
    } finally {
      vi.useRealTimers();
    }
  });
});
