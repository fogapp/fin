import { formatCurrency } from "@/lib/utils";
import type { RecurringOccurrence, RecurringOccurrenceStatus } from "@/api/types";

/** The one status → dot-style mapping, shared by the evidence strip and the
 *  charge calendar. Green = paid as expected, amber = paid at a different
 *  amount, red = missed, hollow = expected but not yet paid, dimmed = skipped. */
export function occurrenceDotClass(status: RecurringOccurrenceStatus): string {
  switch (status) {
    case "paid": return "bg-positive";
    case "paid_amount_changed": return "bg-warning";
    case "missed": return "bg-negative";
    case "skipped": return "bg-muted-foreground/30";
    default: return "border border-muted-foreground/50 bg-transparent";
  }
}

export function statusLabel(o: RecurringOccurrence): string {
  switch (o.status) {
    case "paid": return `paid ${o.amount != null ? formatCurrency(o.amount) : ""}`.trim();
    case "paid_amount_changed": return `paid ${o.amount != null ? formatCurrency(o.amount) : ""} (amount changed)`;
    case "missed": return "missed";
    case "skipped": return "skipped";
    case "due": return "due";
    default: return "upcoming";
  }
}
