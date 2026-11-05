import type { CashTransaction, TransactionContext } from "@/api/types";

/** A transaction page context with nothing to say beyond the row itself —
 *  for suites that drive the detail page but aren't about its story. */
export function quietTransactionContext(tx: CashTransaction): TransactionContext {
  return {
    history: {
      basis: tx.merchant_id ? "merchant" : "description",
      label: tx.merchant_name ?? tx.description ?? null,
      total: 1,
      rows: [{
        id: tx.id, transaction_date: tx.transaction_date, description: tx.description ?? null, amount: tx.amount,
        account_name: tx.account_name ?? null, merchant_name: tx.merchant_name ?? null,
        category_id: tx.category_id ?? null, category_name: tx.category_name ?? null, transfer_id: tx.transfer_id ?? null,
      }],
    },
    stats: null,
    cadence: null,
    series: null,
    treatment: { spend: tx.amount < 0, income: false, budget: tx.amount < 0, merchant_excluded: false },
    budget: null,
    duplicates: [],
    related: [],
    same_day: { total: 0, rows: [] },
    suggested_category: null,
  };
}
