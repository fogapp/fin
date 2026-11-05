import { describe, it, expect } from "vitest";
import { buildTransactionsCsv } from "./csv";
import type { CashTransaction } from "@/api/types";

function tx(overrides: Partial<CashTransaction>): CashTransaction {
  return {
    id: "t1", source: "credit_card", transaction_date: "2026-01-15",
    transfer_id: null, post_date: "2026-01-16", description: "CARD PURCHASE",
    amount: -12.5, transaction_type: "Sale",
    category_id: null, category_name: "Groceries",
    merchant_id: null, merchant_name: "Costco",
    account_id: null, account_name: "Sapphire",
    balance: null, memo: null, loan_id: null, loan_name: null,
    tags: [], created_at: "2026-01-15T00:00:00Z",
    ...overrides,
  } as CashTransaction;
}

describe("buildTransactionsCsv", () => {
  it("emits a header plus one quoted row per transaction", () => {
    const csv = buildTransactionsCsv([tx({})]);
    const lines = csv.split("\n");
    expect(lines).toHaveLength(2);
    expect(lines[0]).toContain('"Date","Post date","Description"');
    expect(lines[1]).toBe(
      '"2026-01-15","2026-01-16","CARD PURCHASE","Costco","Groceries","Sapphire","-12.5","Sale","credit_card","",""',
    );
  });

  it("escapes embedded quotes and preserves commas inside fields", () => {
    const csv = buildTransactionsCsv([
      tx({ description: 'BOB\'S "BEST" DINER, INC', memo: "split, with Sam" }),
    ]);
    expect(csv.split("\n")[1]).toContain('"BOB\'S ""BEST"" DINER, INC"');
    expect(csv.split("\n")[1]).toContain('"split, with Sam"');
  });

  it("joins tag names with semicolons and blanks out nulls", () => {
    const csv = buildTransactionsCsv([
      tx({
        tags: [{ id: "1", name: "travel" }, { id: "2", name: "reimbursable" }] as CashTransaction["tags"],
        merchant_name: null,
      }),
    ]);
    const row = csv.split("\n")[1];
    expect(row).toContain('"travel; reimbursable"');
    expect(row).toContain('"2026-01-15","2026-01-16","CARD PURCHASE",""');
  });
});
