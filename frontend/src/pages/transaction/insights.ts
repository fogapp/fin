import { formatCurrency, formatDate } from "@/lib/utils";
import type { CashTransaction, TransactionContext } from "@/api/types";

// ── Reading a transaction against its context ────────────────────────────────
// Pure functions from (row, context) to the page's sentences and signals, so
// the wording and thresholds live in one tested place instead of inline JSX.

/** Peers at or past this multiple of the median read as unusually large. */
export const UNUSUAL_HIGH = 1.5;
export const UNUSUAL_LOW = 0.5;
/** Share of a merchant's other charges that must agree before suggesting their category. */
export const CATEGORY_AGREEMENT = 0.6;

export type InsightTone = "neutral" | "warning" | "positive";
export type InsightTarget = "history" | "recurrence" | "budget" | "around" | "manage";

export interface Insight {
  key: string;
  label: string;
  tone: InsightTone;
  /** The page section that explains it. */
  target: InsightTarget;
}

/** Where the history is from, in words: "Starbucks" or "charges like this". */
export function peerLabel(ctx: TransactionContext): string {
  return ctx.history.basis === "merchant" && ctx.history.label ? ctx.history.label : "charges like this";
}

/** "2.3× your usual" — the amount against the median of its peers, when there are enough to say. */
export function amountVerdict(ctx: TransactionContext): { tone: InsightTone; label: string } | null {
  const s = ctx.stats;
  if (!s || s.count < 3 || s.ratio_to_median == null) return null;
  if (s.ratio_to_median >= UNUSUAL_HIGH) return { tone: "warning", label: `${s.ratio_to_median.toFixed(1)}× your usual` };
  if (s.ratio_to_median <= UNUSUAL_LOW) return { tone: "neutral", label: "Smaller than usual" };
  // A typical amount isn't something that stands out — no chip.
  return null;
}

/** The one-line headline over the history chart. */
export function historyHeadline(tx: CashTransaction, ctx: TransactionContext): string {
  const where = ctx.history.basis === "merchant" ? `at ${peerLabel(ctx)}` : "with this description";
  const s = ctx.stats;
  if (!s) return `The first charge ${where}.`;

  const nth = `Charge ${s.ordinal} of ${s.count} ${where}`;
  const ratio = s.ratio_to_median;
  if (s.count < 3 || ratio == null) return `${nth}.`;
  if (ratio >= UNUSUAL_HIGH) return `${nth} — ${ratio.toFixed(1)}× the usual ${formatCurrency(s.median)}.`;
  if (ratio <= UNUSUAL_LOW) return `${nth} — well under the usual ${formatCurrency(s.median)}.`;
  if (Math.abs(tx.amount) === s.max && s.max > s.p75 && s.count > 3) return `${nth} — the largest yet.`;
  return `${nth} — right around the usual ${formatCurrency(s.median)}.`;
}

/** The chips under the header: each one a fact about this row with a section that explains it. */
export function insights(tx: CashTransaction, ctx: TransactionContext): Insight[] {
  const out: Insight[] = [];

  const verdict = amountVerdict(ctx);
  if (verdict) out.push({ key: "amount", ...verdict, target: "history" });
  if (ctx.history.total <= 1 && ctx.history.basis === "merchant") {
    out.push({ key: "first", label: `First time at ${peerLabel(ctx)}`, tone: "neutral", target: "history" });
  }

  if (ctx.series && ["active", "suggested", "lapsed"].includes(ctx.series.status)) {
    const what = ctx.series.kind === "bill" ? "bill" : "subscription";
    const label = ctx.series.status === "suggested" ? `Possible ${what}` : `${ctx.series.cadence_description} ${what}`;
    out.push({ key: "series", label, tone: "neutral", target: "recurrence" });
  } else if (ctx.cadence?.includes_transaction) {
    out.push({ key: "cadence", label: `Repeats ${ctx.cadence.description.toLowerCase()}`, tone: "neutral", target: "recurrence" });
  } else {
    const rhythm = roughRhythm(ctx);
    if (rhythm) out.push({ key: "cadence", label: `Recurs ${rhythm.phrase}`, tone: "neutral", target: "recurrence" });
  }

  if (ctx.duplicates.length > 0) out.push({ key: "duplicate", label: "Possible duplicate", tone: "warning", target: "manage" });

  const refund = ctx.related[0];
  if (refund && tx.amount < 0 && Math.abs(refund.amount) >= Math.abs(tx.amount) * 0.95) {
    out.push({ key: "refund", label: `Refunded ${formatDate(refund.transaction_date)}`, tone: "positive", target: "around" });
  } else if (refund && tx.amount > 0) {
    out.push({ key: "refund", label: `Refund of a ${formatCurrency(Math.abs(refund.amount))} charge`, tone: "positive", target: "around" });
  }

  if (tx.budget_excluded) out.push({ key: "budget", label: "Left out of budgets", tone: "neutral", target: "manage" });
  if (ctx.treatment.merchant_excluded) out.push({ key: "excluded", label: "Merchant excluded from spending", tone: "neutral", target: "manage" });
  if (ctx.budget?.available != null && ctx.budget.actual > ctx.budget.available && ctx.budget.before <= ctx.budget.available) {
    out.push({ key: "over", label: "Pushed the budget over", tone: "warning", target: "budget" });
  }

  return out;
}

export interface Rhythm {
  /** "about once a month" */
  phrase: string;
  /** A TrackSubscriptionDialog cadence key. */
  cadenceKey: "week-1" | "week-2" | "month-1" | "month-3" | "year-1";
}

const RHYTHMS: { min: number; max: number; rhythm: Rhythm }[] = [
  { min: 6, max: 8, rhythm: { phrase: "about once a week", cadenceKey: "week-1" } },
  { min: 12, max: 16, rhythm: { phrase: "about every two weeks", cadenceKey: "week-2" } },
  { min: 25, max: 35, rhythm: { phrase: "about once a month", cadenceKey: "month-1" } },
  { min: 80, max: 100, rhythm: { phrase: "about every three months", cadenceKey: "month-3" } },
  { min: 340, max: 390, rhythm: { phrase: "about once a year", cadenceKey: "year-1" } },
];

/**
 * A looser read than the cadence detector: the same price, at a steady
 * interval, but not on a fixed day — the shape of a subscription whose
 * charge date drifts (or a statement date that moves). The detector rightly
 * won't forecast that; the page can still say it looks recurring.
 */
export function roughRhythm(ctx: TransactionContext): Rhythm | null {
  const s = ctx.stats;
  if (ctx.cadence || !s || s.count < 4 || s.median <= 0) return null;
  // Spread of the middle half of amounts — a subscription's price barely moves.
  if ((s.p75 - s.p25) / s.median > 0.15) return null;

  const dates = ctx.history.rows.map((r) => r.transaction_date).sort();

  // One charge in each of N consecutive months, whatever the day: monthly.
  const months = dates.map((d) => +d.slice(0, 4) * 12 + +d.slice(5, 7));
  if (new Set(months).size === months.length && months[months.length - 1] - months[0] === months.length - 1) {
    return RHYTHMS.find((r) => r.rhythm.cadenceKey === "month-1")!.rhythm;
  }

  const gaps = dates.slice(1).map((d, i) => daysBetween(dates[i], d)).sort((a, b) => a - b);
  if (gaps.length < 3) return null;
  const median = gaps[Math.floor(gaps.length / 2)];
  // Most gaps must sit near the median, or it's a habit, not a schedule.
  const steady = gaps.filter((g) => Math.abs(g - median) <= Math.max(4, median * 0.25)).length / gaps.length;
  if (steady < 0.75) return null;
  return RHYTHMS.find((r) => median >= r.min && median <= r.max)?.rhythm ?? null;
}

/** What one occurrence of the row is called: a charge, a deposit, or a payment between accounts. */
export function occurrenceNoun(tx: Pick<CashTransaction, "amount" | "transfer_id">): "charge" | "deposit" | "payment" {
  if (tx.transfer_id) return "payment";
  return tx.amount > 0 ? "deposit" : "charge";
}

/** Only charges can become subscriptions — not deposits, not transfers. */
export function canTrackAsSubscription(tx: Pick<CashTransaction, "amount" | "transfer_id">): boolean {
  return tx.amount < 0 && !tx.transfer_id;
}

/** "31%", or "under 1%" rather than a misleading "0%". */
export function shareLabel(share: number): string {
  if (share > 0 && share < 0.01) return "under 1%";
  return `${Math.round(share * 100)}%`;
}

/** Why a row does or doesn't count as spending, in words. */
export function spendReason(tx: CashTransaction, ctx: TransactionContext): string {
  if (ctx.treatment.spend) {
    return tx.transfer_id ? "Counted in spending (the transfer opts in)" : "Counted in spending";
  }
  if (ctx.treatment.income) return "Counted as income";
  if (tx.transfer_id) return "Not spending — money moving between your accounts";
  if (ctx.treatment.merchant_excluded) return "Not spending — the merchant is excluded";
  if (tx.transaction_type === "Payment") return "Not spending — a card payment";
  if (tx.amount > 0) return "A credit — not counted as income";
  return "Not counted in spending";
}

/** The category the merchant's other charges agree on, when it isn't this row's. */
export function categorySuggestion(ctx: TransactionContext) {
  const s = ctx.suggested_category;
  if (!s || s.of === 0 || s.count / s.of < CATEGORY_AGREEMENT) return null;
  return s;
}

/** Peers without a category that this row's category could be applied to. */
export function uncategorizedPeers(tx: CashTransaction, ctx: TransactionContext): string[] {
  if (!tx.category_id || ctx.history.basis === "none") return [];
  return ctx.history.rows.filter((r) => r.id !== tx.id && !r.category_id && !r.transfer_id).map((r) => r.id);
}

/** Days from `from` to `to` (yyyy-mm-dd), as calendar days. */
export function daysBetween(from: string, to: string): number {
  const a = Date.UTC(+from.slice(0, 4), +from.slice(5, 7) - 1, +from.slice(8, 10));
  const b = Date.UTC(+to.slice(0, 4), +to.slice(5, 7) - 1, +to.slice(8, 10));
  return Math.round((b - a) / 86_400_000);
}

/** "3 days later", "the same day", "2 days earlier". */
export function relativeDays(diff: number): string {
  if (diff === 0) return "the same day";
  const n = Math.abs(diff);
  return `${n} day${n === 1 ? "" : "s"} ${diff > 0 ? "later" : "earlier"}`;
}

/** Bring a story section into view (the insight chips' jump). */
export function scrollToSection(target: InsightTarget) {
  document.getElementById(`txn-${target}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
}
