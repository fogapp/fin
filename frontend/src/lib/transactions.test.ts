import { describe, it, expect } from "vitest";
import {
  amountColor,
  isCardPaymentCredit,
  normalizeDescription,
  paymentSettlementStatus,
  transactionTypeLabel,
} from "./transactions";
import type { CashTransaction } from "@/api/types";

function tx(overrides: Partial<CashTransaction> = {}): CashTransaction {
  return {
    id: "t1", source: "credit_card", transaction_date: "2026-09-17", transfer_id: null,
    transfer_kind: null, transfer_include_in_spend: null, post_date: null,
    description: "AUTOMATIC PAYMENT - THANK", amount: 845.23, transaction_type: "Return",
    category_id: null, category_name: null, category_parent_name: null, merchant_id: null,
    merchant_name: null, account_id: "a1", account_name: "Amazon Card", balance: null, memo: null,
    loan_id: null, loan_name: null, tags: [], created_at: "2026-09-18T00:00:00Z",
    ...overrides,
  };
}

describe("normalizeDescription", () => {
  it.each([
    ["APPLECARD GSBANK PAYMENT 100001 WEB ID: 9999999999", "APPLECARD GSBANK PAYMENT"],
    ["Online Payment 10000000001 To Auto Loan 1111 09/02", "Online Payment To Auto Loan 1111"],
    ["CHASE CREDIT CRD AUTOPAY 0000XXXXX123456 PPD ID: 12345", "CHASE CREDIT CRD AUTOPAY"],
    ["Payment to Chase card ending in 4321 08/26", "Payment to Chase card ending in 4321"],
    ["Zelle payment to Jordan Smith 10000000003", "Zelle payment to Jordan Smith"],
    ["AUTOMATIC PAYMENT - THANK", "AUTOMATIC PAYMENT - THANK"],
    ["SQ *CAFE 0042", "SQ *CAFE 0042"],
    ["", ""],
  ])("%s → %s", (raw, stable) => {
    expect(normalizeDescription(raw)).toBe(stable);
  });
});

describe("transactionTypeLabel", () => {
  it("reports the transfer kind for a linked row and the raw type otherwise", () => {
    expect(transactionTypeLabel(tx({ transfer_id: "tr1", transfer_kind: "credit_card_payment" }))).toBe("Card payment");
    expect(transactionTypeLabel(tx({ transfer_id: "tr1", transfer_kind: "loan_payment" }))).toBe("Loan payment");
    expect(transactionTypeLabel(tx({ transfer_id: "tr1", transfer_kind: "transfer" }))).toBe("Transfer");
    expect(transactionTypeLabel(tx())).toBe("Return");
  });
});

describe("amountColor", () => {
  it("tints linked transfer legs amber ahead of the income green", () => {
    expect(amountColor(tx({ transfer_id: "tr1" }))).toBe("text-warning");
    expect(amountColor(tx())).toBe("text-positive");
    expect(amountColor(tx({ source: "bank", amount: 100, transaction_type: "Credit" }))).toBe("text-positive");
    expect(amountColor(tx({ amount: -20, transaction_type: "Sale" }))).toBe("");
  });
});

describe("isCardPaymentCredit / paymentSettlementStatus", () => {
  it("recognises a card credit by type or by its payment signature", () => {
    expect(isCardPaymentCredit(tx({ transaction_type: "Payment", description: "PYMT RECVD" }))).toBe(true);
    expect(isCardPaymentCredit(tx({ transaction_type: "Return", description: "AUTOMATIC PAYMENT - THANK" }))).toBe(true);
    expect(isCardPaymentCredit(tx({ transaction_type: "Return", description: "Amazon.com" }))).toBe(false);
    expect(isCardPaymentCredit(tx({ source: "bank", transaction_type: "Credit", description: "AUTOMATIC PAYMENT - THANK" }))).toBe(false);
    expect(isCardPaymentCredit(tx({ amount: -845.23, transaction_type: "Payment" }))).toBe(false);
  });

  it("reports awaiting inside the settlement window, unmatched after it, null once linked", () => {
    const now = new Date("2026-09-20T12:00:00Z");
    expect(paymentSettlementStatus(tx(), now)).toBe("awaiting");
    expect(paymentSettlementStatus(tx({ transaction_date: "2026-09-01" }), now)).toBe("unmatched");
    expect(paymentSettlementStatus(tx({ transfer_id: "tr1" }), now)).toBeNull();
    expect(paymentSettlementStatus(tx({ description: "Amazon.com" }), now)).toBeNull();
  });
});
