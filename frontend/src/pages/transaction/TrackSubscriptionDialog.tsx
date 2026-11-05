import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogHeader, DialogFooter } from "@/components/ui/dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import { formatCurrency, formatDate } from "@/lib/utils";
import { normalizeDescription } from "@/lib/transactions";
import type { CashTransaction, TransactionContext } from "@/api/types";

// ── Track as subscription ─────────────────────────────────────────────────────
// Creates a manual series from this charge, prefilled from the cadence the
// context detected: the schedule, the stream's average amount, and — the
// point of doing it from here — the earlier matched charges as its paid
// history, so the new subscription starts with its track record instead of
// one lonely occurrence.

const CADENCES = [
  { key: "week-1", label: "Weekly", granularity: "week", quantity: 1 },
  { key: "week-2", label: "Every 2 weeks", granularity: "week", quantity: 2 },
  { key: "month-1", label: "Monthly", granularity: "month", quantity: 1 },
  { key: "month-3", label: "Every 3 months", granularity: "month", quantity: 3 },
  { key: "month-6", label: "Every 6 months", granularity: "month", quantity: 6 },
  { key: "year-1", label: "Yearly", granularity: "year", quantity: 1 },
] as const;

type Cadence = (typeof CADENCES)[number];

/** The schedule's anchor: the detected one when the cadence is unchanged, else this charge's date. */
function anchorFor(c: Cadence, tx: CashTransaction, detected: TransactionContext["cadence"]): Record<string, unknown> {
  if (detected && detected.granularity === c.granularity && detected.quantity === c.quantity) return detected.anchor;
  const [y, m, d] = tx.transaction_date.split("-").map(Number);
  if (c.granularity === "week") return { weekday: new Date(Date.UTC(y, m - 1, d)).getUTCDay() };
  if (c.granularity === "year") return { month: m, day: d };
  return { day_of_month: d };
}

export function TrackSubscriptionDialog({ tx, ctx, presetCadence, onClose }: {
  tx: CashTransaction;
  ctx: TransactionContext;
  /** A cadence key to start from when the detector found none (a rough rhythm). */
  presetCadence?: string;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const detected = ctx.cadence;
  const initialKey = CADENCES.find((c) => c.granularity === detected?.granularity && c.quantity === detected?.quantity)?.key ?? presetCadence ?? "month-1";
  const history = (detected?.matched_ids ?? []).filter((id) => id !== tx.id);
  // Fixed-price streams are subscriptions; ones whose amount moves are bills.
  const variable = ctx.stats ? ctx.stats.p75 - ctx.stats.p25 > ctx.stats.median * 0.1 : false;

  const [name, setName] = useState(tx.merchant_name ?? (normalizeDescription(tx.description) || tx.description || ""));
  const [kind, setKind] = useState<"subscription" | "bill">(variable ? "bill" : "subscription");
  const [cadenceKey, setCadenceKey] = useState<string>(initialKey);
  const [amount, setAmount] = useState(String(detected?.average_amount ?? Math.abs(tx.amount)));
  const [withHistory, setWithHistory] = useState(history.length > 0);

  const create = useMutation({
    mutationFn: () => {
      const c = CADENCES.find((x) => x.key === cadenceKey) ?? CADENCES[2];
      return api.post<{ id: string; name: string }>("/subscriptions", {
        name: name.trim(),
        kind,
        granularity: c.granularity,
        quantity: c.quantity,
        anchor: anchorFor(c, tx, detected),
        average_amount: Number(amount),
        ...(tx.merchant_id ? { merchant_id: tx.merchant_id } : { description_pattern: tx.description ?? "" }),
        ...(tx.account_id ? { account_id: tx.account_id } : {}),
        cash_transaction_id: tx.id,
        history_transaction_ids: withHistory ? history : [],
      });
    },
    onSuccess: (series) => {
      invalidate(qc, keys.subscriptions, keys.transactionContext, keys.budget);
      toast.success(`Tracking ${series.name}`);
      onClose();
    },
  });

  const valid = name.trim().length > 0 && Number(amount) > 0;

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent size="md">
        <DialogHeader title="Track as subscription" />
        <form
          onSubmit={(e) => { e.preventDefault(); if (valid) create.mutate(); }}
          className="space-y-4 px-5 py-4"
        >
          {detected && (
            <p className="rounded-lg bg-muted/40 px-3 py-2 text-xs text-muted-foreground">
              Fin found {detected.matched_count} charges {detected.description.toLowerCase()}
              {detected.missed_count > 0 && `, with ${detected.missed_count} gap${detected.missed_count === 1 ? "" : "s"}`}.
              The next one would land around {formatDate(detected.next_expected_date)}.
            </p>
          )}

          <Field label="Name" htmlFor="track-name" required>
            <Input id="track-name" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          </Field>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Repeats" htmlFor="track-cadence">
              <Select id="track-cadence" value={cadenceKey} onChange={(e) => setCadenceKey(e.target.value)}>
                {CADENCES.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
              </Select>
            </Field>
            <Field label="Usual amount" htmlFor="track-amount" required>
              <Input id="track-amount" type="number" step="0.01" min="0" inputMode="decimal"
                value={amount} onChange={(e) => setAmount(e.target.value)} />
            </Field>
          </div>

          <Field label="Kind" htmlFor="track-kind">
            <Select id="track-kind" value={kind} onChange={(e) => setKind(e.target.value as "subscription" | "bill")}>
              <option value="subscription">Subscription — the same price each time</option>
              <option value="bill">Bill — the amount varies</option>
            </Select>
          </Field>

          {history.length > 0 && (
            <div className="flex items-start gap-2">
              <Checkbox id="track-history" checked={withHistory} onChange={(e) => setWithHistory(e.target.checked)} />
              <Label htmlFor="track-history" className="font-normal leading-snug">
                Include the {history.length} earlier matching charge{history.length === 1 ? "" : "s"} as its history
                <span className="block text-caption text-muted-foreground">
                  Totals {formatCurrency(history.reduce((sum, id) => sum + Math.abs(ctx.history.rows.find((r) => r.id === id)?.amount ?? 0), 0))} before this one
                </span>
              </Label>
            </div>
          )}

          <DialogFooter className="-mx-5 -mb-4 mt-2">
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit" disabled={!valid || create.isPending}>
              {create.isPending ? "Saving…" : "Track subscription"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
