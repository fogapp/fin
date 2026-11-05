import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, Check, CircleDashed, Minus, X } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { Drawer, DrawerContent, DrawerHeader, DrawerFooter } from "@/components/ui/drawer";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/components/ui/toast";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import type { RecurringOccurrence, SubscriptionDetail } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// Detail drawer for one recurring series: the full occurrence history
// (the "is this actually recurring?" evidence), a price sparkline, matching
// criteria editing, and every lifecycle action valid for its status.
export function SeriesDrawer({ id, onClose }: { id: string | null; onClose: () => void }) {
  return (
    <Drawer open={id != null} onOpenChange={(open) => !open && onClose()}>
      {id != null && <SeriesDrawerContent id={id} onClose={onClose} />}
    </Drawer>
  );
}

function SeriesDrawerContent({ id, onClose }: { id: string; onClose: () => void }) {
  const qc = useQueryClient();
  const confirmDialog = useConfirm();
  const { data: series, isLoading } = useQuery(queries.subscription(id));
  const [editing, setEditing] = useState(false);

  const refresh = () => invalidate(qc, keys.subscriptions);

  const lifecycle = useMutation({
    mutationFn: (verb: "accept" | "dismiss" | "restore" | "end") => api.post(`/subscriptions/${id}/${verb}`, {}),
    onSuccess: () => {
      refresh();
      toast.success("Updated");
    },
    onError: () => toast.error("Action failed"),
  });

  const destroy = useMutation({
    mutationFn: () => api.delete(`/subscriptions/${id}`),
    onSuccess: () => {
      refresh();
      toast.success("Subscription deleted");
      onClose();
    },
    onError: () => toast.error("Delete failed"),
  });

  const occurrenceAction = useMutation({
    mutationFn: ({ occurrenceId, verb }: { occurrenceId: string; verb: "skip" | "detach" }) =>
      api.post(`/subscriptions/${id}/occurrences/${occurrenceId}/${verb}`, {}),
    onSuccess: () => refresh(),
    onError: () => toast.error("Action failed"),
  });

  async function handleDelete() {
    const ok = await confirmDialog({
      title: "Delete this subscription?",
      description: "Its history and evidence are removed permanently. Ending it instead keeps the record.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (ok) destroy.mutate();
  }

  return (
    <DrawerContent className="sm:w-[430px]">
      <DrawerHeader title={series?.name ?? "Subscription"} />
      {isLoading || !series ? (
        <div className="space-y-3 p-4">
          {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-10 rounded-lg" />)}
        </div>
      ) : (
        <>
          <div className="flex-1 space-y-5 overflow-y-auto p-4">
            <SeriesFacts series={series} />
            {editing ? (
              <EditForm key={series.id} series={series} onDone={() => setEditing(false)} />
            ) : (
              <Button size="sm" variant="outline" onClick={() => setEditing(true)}>Edit details</Button>
            )}
            <PriceSparkline occurrences={series.occurrences} />
            <OccurrenceHistory
              series={series}
              onSkip={(occurrenceId) => occurrenceAction.mutate({ occurrenceId, verb: "skip" })}
              onDetach={(occurrenceId) => occurrenceAction.mutate({ occurrenceId, verb: "detach" })}
            />
          </div>
          <DrawerFooter>
            <div className="flex w-full flex-wrap gap-2">
              {series.status === "suggested" && (
                <>
                  <Button className="flex-1" onClick={() => lifecycle.mutate("accept")} disabled={lifecycle.isPending}>
                    <Check size={14} /> Accept
                  </Button>
                  <Button className="flex-1" variant="outline" onClick={() => lifecycle.mutate("dismiss")} disabled={lifecycle.isPending}>
                    <X size={14} /> Dismiss
                  </Button>
                </>
              )}
              {(series.status === "active" || series.status === "lapsed") && (
                <>
                  <Button className="flex-1" variant="outline" onClick={() => lifecycle.mutate("end")} disabled={lifecycle.isPending}>
                    End subscription
                  </Button>
                  <Button variant="outline" className="text-destructive" onClick={handleDelete}>Delete</Button>
                </>
              )}
              {(series.status === "dismissed" || series.status === "ended") && (
                <>
                  <Button className="flex-1" variant="outline" onClick={() => lifecycle.mutate("restore")} disabled={lifecycle.isPending}>
                    Restore
                  </Button>
                  <Button variant="outline" className="text-destructive" onClick={handleDelete}>Delete</Button>
                </>
              )}
            </div>
          </DrawerFooter>
        </>
      )}
    </DrawerContent>
  );
}

function SeriesFacts({ series }: { series: SubscriptionDetail }) {
  const facts: Array<[string, React.ReactNode]> = [
    ["Status", <StatusBadge key="s" series={series} />],
    ["Amount", `${series.kind === "bill" ? "~" : ""}${formatCurrency(series.average_amount)}${series.kind === "bill" && series.min_amount != null && series.max_amount != null ? ` (${formatCurrency(series.min_amount)}–${formatCurrency(series.max_amount)})` : ""}`],
    ["Cadence", series.cadence_description],
    ["Monthly equivalent", formatCurrency(series.monthly_equivalent)],
    ["Next expected", series.next_expected_date ? formatDate(series.next_expected_date) : "—"],
    ["Last charge", series.last_charge_date ? formatDate(series.last_charge_date) : "—"],
    ["Confidence", series.confidence_label],
    ["Source", series.source === "manual" ? "added manually" : "detected"],
  ];
  return (
    <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
      {facts.map(([label, value]) => (
        <div key={label as string}>
          <dt className="text-xs text-muted-foreground">{label}</dt>
          <dd className="mt-0.5">{value}</dd>
        </div>
      ))}
      {series.notes && (
        <div className="col-span-2">
          <dt className="text-xs text-muted-foreground">Notes</dt>
          <dd className="mt-0.5 whitespace-pre-wrap">{series.notes}</dd>
        </div>
      )}
    </dl>
  );
}

function StatusBadge({ series }: { series: SubscriptionDetail }) {
  const variant = series.status === "active" ? "success" : series.status === "lapsed" ? "destructive" : "outline";
  return (
    <span className="flex items-center gap-1.5">
      <Badge variant={variant}>{series.status}</Badge>
      {series.at_risk && <Badge variant="outline" className="border-warning/40 text-warning">missed payment</Badge>}
    </span>
  );
}

// Inline SVG price history across paid occurrences — enough to see a hike at
// a glance without pulling in a chart library for 20 points.
function PriceSparkline({ occurrences }: { occurrences: RecurringOccurrence[] }) {
  const paid = occurrences
    .filter((o) => (o.status === "paid" || o.status === "paid_amount_changed") && o.amount != null)
    .slice(-24);
  if (paid.length < 2) return null;

  const amounts = paid.map((o) => o.amount as number);
  const min = Math.min(...amounts);
  const max = Math.max(...amounts);
  const spread = max - min || 1;
  const w = 100;
  const h = 28;
  const points = amounts
    .map((a, i) => `${(i / (amounts.length - 1)) * w},${h - 4 - ((a - min) / spread) * (h - 8)}`)
    .join(" ");

  return (
    <div>
      <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Price History</p>
      <div className="rounded-lg border p-3">
        <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="h-10 w-full text-primary" aria-hidden>
          <polyline points={points} fill="none" stroke="currentColor" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
        </svg>
        <div className="mt-1 flex justify-between text-xs tabular-nums text-muted-foreground">
          <span>{formatCurrency(min)}</span>
          <span>{formatCurrency(max)}</span>
        </div>
      </div>
    </div>
  );
}

function OccurrenceHistory({ series, onSkip, onDetach }: {
  series: SubscriptionDetail;
  onSkip: (occurrenceId: string) => void;
  onDetach: (occurrenceId: string) => void;
}) {
  const rows = [...series.occurrences].reverse();
  if (rows.length === 0) return null;

  return (
    <div>
      <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">History</p>
      <ul className="divide-y rounded-lg border">
        {rows.map((o) => (
          <li key={o.id} className="flex items-center gap-2.5 px-3 py-2 text-sm">
            <OccurrenceGlyph occurrence={o} />
            <div className="min-w-0 flex-1">
              <p className="whitespace-nowrap">
                {formatDate(o.charged_date ?? o.expected_date)}
                {o.charged_date && o.charged_date !== o.expected_date && (
                  <span className="ml-1 text-xs text-muted-foreground">(expected {formatDate(o.expected_date)})</span>
                )}
              </p>
              {o.transaction && (
                <p className="truncate text-xs text-muted-foreground">
                  {o.transaction.description}{o.transaction.account_name ? ` · ${o.transaction.account_name}` : ""}
                </p>
              )}
            </div>
            <span className={cn("tabular-nums", o.status === "missed" && "text-muted-foreground")}>
              {o.amount != null ? formatCurrency(o.amount) : o.expected_amount != null ? formatCurrency(o.expected_amount) : "—"}
            </span>
            {o.amount_delta != null && o.amount_delta !== 0 && (
              <span className={cn("text-xs tabular-nums", o.amount_delta > 0 ? "text-negative" : "text-positive")}>
                {o.amount_delta > 0 ? "+" : ""}{formatCurrency(o.amount_delta)}
              </span>
            )}
            {o.status === "missed" && (
              <Button size="sm" variant="ghost" className="text-xs" onClick={() => onSkip(o.id)}>Skip</Button>
            )}
            {(o.status === "paid" || o.status === "paid_amount_changed") && o.cash_transaction_id && (
              <Button size="sm" variant="ghost" className="text-xs" onClick={() => onDetach(o.id)}>Detach</Button>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

function OccurrenceGlyph({ occurrence }: { occurrence: RecurringOccurrence }) {
  switch (occurrence.status) {
    case "paid":
      return <Check size={14} className="shrink-0 text-positive" aria-label="paid" />;
    case "paid_amount_changed":
      return <AlertTriangle size={14} className="shrink-0 text-warning" aria-label="paid, amount changed" />;
    case "missed":
      return <X size={14} className="shrink-0 text-negative" aria-label="missed" />;
    case "skipped":
      return <Minus size={14} className="shrink-0 text-muted-foreground" aria-label="skipped" />;
    default:
      return <CircleDashed size={14} className="shrink-0 text-muted-foreground" aria-label="upcoming" />;
  }
}

function EditForm({ series, onDone }: { series: SubscriptionDetail; onDone: () => void }) {
  const qc = useQueryClient();
  const [name, setName] = useState(series.name);
  const [kind, setKind] = useState(series.kind);
  const [tolerancePct, setTolerancePct] = useState(String(Math.round(series.amount_tolerance * 100)));
  const [granularity, setGranularity] = useState(series.granularity);
  const [quantity, setQuantity] = useState(String(series.quantity));
  const [dayOfMonth, setDayOfMonth] = useState(
    typeof series.anchor.day_of_month === "number" || typeof series.anchor.day_of_month === "string"
      ? String(series.anchor.day_of_month)
      : "",
  );
  const [notes, setNotes] = useState(series.notes ?? "");

  const save = useMutation({
    mutationFn: () => {
      const body: Record<string, unknown> = {
        name,
        kind,
        notes,
        amount_tolerance: Math.min(Math.max(Number(tolerancePct) / 100, 0.01), 0.9),
        granularity,
        quantity: Number(quantity) || 1,
      };
      if (granularity === "month" && dayOfMonth) {
        body.anchor = { day_of_month: dayOfMonth === "last" ? "last" : Number(dayOfMonth) };
      }
      return api.patch(`/subscriptions/${series.id}`, body);
    },
    onSuccess: () => {
      invalidate(qc, keys.subscriptions);
      toast.success("Subscription updated");
      onDone();
    },
    onError: () => toast.error("Update failed"),
  });

  return (
    <form
      className="space-y-3 rounded-lg border p-3"
      onSubmit={(e) => {
        e.preventDefault();
        save.mutate();
      }}
    >
      <Field label="Name" htmlFor="series-name">
        <Input id="series-name" value={name} onChange={(e) => setName(e.target.value)} required />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Type" htmlFor="series-kind">
          <Select id="series-kind" value={kind} onChange={(e) => setKind(e.target.value as typeof kind)}>
            <option value="subscription">Subscription (fixed)</option>
            <option value="bill">Bill (variable)</option>
          </Select>
        </Field>
        <Field label="Amount tolerance %" htmlFor="series-tolerance">
          <Input id="series-tolerance" type="number" min={1} max={90} value={tolerancePct} onChange={(e) => setTolerancePct(e.target.value)} />
        </Field>
      </div>
      <div className="grid grid-cols-3 gap-3">
        <Field label="Every" htmlFor="series-quantity">
          <Input id="series-quantity" type="number" min={1} value={quantity} onChange={(e) => setQuantity(e.target.value)} />
        </Field>
        <Field label="Period" htmlFor="series-granularity">
          <Select id="series-granularity" value={granularity} onChange={(e) => setGranularity(e.target.value as typeof granularity)}>
            <option value="week">week(s)</option>
            <option value="month">month(s)</option>
            <option value="year">year(s)</option>
          </Select>
        </Field>
        {granularity === "month" && (
          <Field label="On day" htmlFor="series-day-of-month">
            <Input id="series-day-of-month" value={dayOfMonth} onChange={(e) => setDayOfMonth(e.target.value)} placeholder="15 or last" />
          </Field>
        )}
      </div>
      <Field label="Notes" htmlFor="series-notes">
        <Textarea id="series-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
      </Field>
      <div className="flex justify-end gap-2">
        <Button type="button" size="sm" variant="ghost" onClick={onDone}>Cancel</Button>
        <Button type="submit" size="sm" disabled={save.isPending}>Save</Button>
      </div>
    </form>
  );
}
