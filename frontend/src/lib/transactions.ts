import type { CashTransaction, TransferKind } from "@/api/types";

/**
 * Descriptors that mark a card-side payment credit or a bank-side payment
 * debit. Mirrors Transfers::PaymentSignals::SIGNATURE_PATTERN on the server.
 */
export const PAYMENT_SIGNATURE = /AUTOPAY|AUTOMATIC\s+PAYMENT|PAYMENT\s*-?\s*THANK|EPAY|GSBANK|CARDMEMBER\s+SERV/i;

const PROCESSOR_TAG = /\b(?:WEB|PPD|CCD|ARC|TEL|POS)\s+ID:?\s*\S*/gi;
const DATE_TOKEN    = /\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b/g;
const REFERENCE_DIGITS = 5;

/**
 * The stable text of a descriptor: reference numbers, processor tags and
 * dates stripped, so an automation built from one occurrence matches the
 * next ("Online Payment 10000000001 To Auto Loan 1111 09/02" becomes
 * "Online Payment To Auto Loan 1111"). Mirrors
 * Transfers::PaymentSignals.normalize_description — keep the two in step.
 */
export function normalizeDescription(description: string | null | undefined): string {
  return (description ?? "")
    .replace(PROCESSOR_TAG, " ")
    .replace(DATE_TOKEN, " ")
    .split(/\s+/)
    .filter((token) => (token.match(/\d/g)?.length ?? 0) < REFERENCE_DIGITS)
    .join(" ")
    .trim()
    .replace(/[\s\-#:*]+$/, "");
}

export function transferKindLabel(kind: TransferKind | null | undefined): string {
  switch (kind) {
    case "credit_card_payment": return "Card payment";
    case "loan_payment":        return "Loan payment";
    default:                    return "Transfer";
  }
}

/**
 * Fin's view of what a row is: the transfer kind when it's linked, else
 * the type the import assigned. The raw type is what the bank said
 * ("Return"); a linked card payment is a card payment regardless.
 */
export function transactionTypeLabel(tx: Pick<CashTransaction, "transaction_type" | "transfer_kind" | "transfer_id">): string {
  if (tx.transfer_id) return transferKindLabel(tx.transfer_kind);
  return tx.transaction_type ?? "—";
}

/**
 * Row/amount tint. A linked transfer leg is amber — it is money moving
 * between your own accounts, so neither green income nor a charge. Otherwise
 * green for money coming in (returns, bank credits).
 */
export function amountColor(tx: Pick<CashTransaction, "transaction_type" | "source" | "amount" | "transfer_id">): string {
  if (tx.transfer_id) return "text-warning";
  if (tx.transaction_type === "Return" || (tx.source === "bank" && tx.amount > 0)) {
    return "text-positive";
  }
  return "";
}

// Matches Transfer::PAYMENT_CANDIDATE_DAYS (±4 days) plus slack for the bank
// leg's posting + sync lag.
const SETTLEMENT_WINDOW_DAYS = 7;

/** A positive row that reads as a card payment: typed so at ingest, or a
 *  card-side credit carrying a payment signature the import didn't act on. */
export function isCardPaymentCredit(tx: Pick<CashTransaction, "source" | "amount" | "transaction_type" | "description">): boolean {
  if (tx.amount <= 0) return false;
  return tx.transaction_type === "Payment" ||
    (tx.source === "credit_card" && PAYMENT_SIGNATURE.test(tx.description ?? ""));
}

/**
 * State of a card-side payment credit ("Automatic payment - thank you") that
 * has no linked transfer yet. The funding bank debit usually posts a day or
 * two later and PaymentMatcher links the pair automatically:
 *
 *   - "awaiting":  recent — the bank leg just hasn't posted/synced yet.
 *   - "unmatched": past the match window — the paying account is likely not
 *                  tracked, so it needs a manual link.
 *   - null: not an unlinked card-side payment credit.
 */
export function paymentSettlementStatus(
  tx: CashTransaction,
  now: Date = new Date(),
): "awaiting" | "unmatched" | null {
  if (tx.transfer_id || !isCardPaymentCredit(tx)) return null;
  const ageDays = (now.getTime() - new Date(`${tx.transaction_date}T00:00:00Z`).getTime()) / 86_400_000;
  return ageDays <= SETTLEMENT_WINDOW_DAYS ? "awaiting" : "unmatched";
}
