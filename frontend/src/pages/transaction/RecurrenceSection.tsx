import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Repeat } from "lucide-react";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";
import { queries } from "@/api/queries";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { OccurrenceDots } from "@/pages/subscriptions/OccurrenceDots";
import { SeriesDrawer } from "@/pages/subscriptions/SeriesDrawer";
import { formatCurrency, formatDate } from "@/lib/utils";
import type { CashTransaction, TransactionContext } from "@/api/types";
import { TrackSubscriptionDialog } from "./TrackSubscriptionDialog";
import { canTrackAsSubscription, daysBetween, occurrenceNoun, roughRhythm } from "./insights";
import { Section } from "./Section";

type Series = NonNullable<TransactionContext["series"]>;

const STATUS_BADGE: Record<Series["status"], { label: string; variant: "default" | "success" | "destructive" | "outline" }> = {
  active:    { label: "Tracking", variant: "success" },
  suggested: { label: "Suggested", variant: "default" },
  lapsed:    { label: "Lapsed", variant: "destructive" },
  ended:     { label: "Ended", variant: "outline" },
  dismissed: { label: "Dismissed", variant: "outline" },
};

/** "Does it repeat?" — the subscription this belongs to, or the cadence
 *  Fin can see in its history, with the one action each calls for. */
export function RecurrenceSection({ tx, ctx }: { tx: CashTransaction; ctx: TransactionContext }) {
  const [tracking, setTracking] = useState(false);
  const [openSeries, setOpenSeries] = useState<string | null>(null);
  const live = ctx.series && ["active", "suggested", "lapsed"].includes(ctx.series.status) ? ctx.series : null;
  const rhythm = roughRhythm(ctx);
  const noun = occurrenceNoun(tx);
  const trackable = canTrackAsSubscription(tx);

  // Nothing recurring to say — the manual "track as subscription" lives in
  // the manage rail rather than as an empty section here.
  if (!live && !ctx.cadence && !rhythm) return null;

  return (
    <>
      {live ? (
        <SeriesView series={live} tx={tx} onManage={() => setOpenSeries(live.id)} />
      ) : ctx.cadence ? (
        <Section
          id="recurrence"
          eyebrow="Repeats"
          headline={
            ctx.cadence.includes_transaction
              ? <>This looks like a {noun} that repeats {ctx.cadence.description.toLowerCase()}.</>
              : <>Some of these {noun}s repeat {ctx.cadence.description.toLowerCase()} — this one is off the pattern.</>
          }
          aside={<Repeat size={16} className="text-muted-foreground" aria-hidden />}
        >
          <p className="text-sm text-muted-foreground">
            {ctx.cadence.matched_count} {noun}s of about {formatCurrency(ctx.cadence.average_amount)} line up on the schedule
            {ctx.cadence.missed_count > 0 && ` (${ctx.cadence.missed_count} missed)`}.
            {" "}At that rate it's {formatCurrency(annualize(ctx.cadence))} a year
            {ctx.cadence.includes_transaction && <>, next around <strong className="font-medium text-foreground">{formatDate(ctx.cadence.next_expected_date)}</strong></>}.
          </p>
          {ctx.series?.status === "dismissed" ? (
            <p className="text-xs text-muted-foreground">
              You dismissed {ctx.series.name} as a subscription.{" "}
              <button onClick={() => setOpenSeries(ctx.series!.id)} className="rounded underline underline-offset-2 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                Review it
              </button>
            </p>
          ) : trackable && (
            <Button size="sm" onClick={() => setTracking(true)}>
              <Repeat size={14} />
              Track as subscription
            </Button>
          )}
        </Section>
      ) : rhythm && (
        <Section
          id="recurrence"
          eyebrow="Repeats"
          headline={trackable
            ? <>Charged {rhythm.phrase} at about {formatCurrency(ctx.stats!.median)} — it looks like a subscription.</>
            : <>A regular {noun} of about {formatCurrency(ctx.stats!.median)}, {rhythm.phrase}.</>}
          aside={<Repeat size={16} className="text-muted-foreground" aria-hidden />}
        >
          {trackable && (
            <>
              <p className="text-sm text-muted-foreground">
                The day it lands moves around, so Fin can't forecast the next one on its own. Tracking it
                puts it with your subscriptions and flags a missed or changed charge.
              </p>
              <Button size="sm" onClick={() => setTracking(true)}>
                <Repeat size={14} />
                Track as subscription
              </Button>
            </>
          )}
        </Section>
      )}

      {tracking && <TrackSubscriptionDialog tx={tx} ctx={ctx} presetCadence={rhythm?.cadenceKey} onClose={() => setTracking(false)} />}
      <SeriesDrawer id={openSeries} onClose={() => setOpenSeries(null)} />
    </>
  );
}

function annualize(c: NonNullable<TransactionContext["cadence"]>): number {
  const perYear = c.granularity === "week" ? 52 / c.quantity : c.granularity === "month" ? 12 / c.quantity : 1 / c.quantity;
  return c.average_amount * perYear;
}

function SeriesView({ series, tx, onManage }: { series: Series; tx: CashTransaction; onManage: () => void }) {
  const qc = useQueryClient();
  const { data: detail } = useQuery(queries.subscription(series.id));
  const lifecycle = useMutation({
    mutationFn: (verb: "accept" | "dismiss") => api.post(`/subscriptions/${series.id}/${verb}`, {}),
    onSuccess: () => invalidate(qc, keys.subscriptions, keys.transactionContext),
  });

  const badge = STATUS_BADGE[series.status];
  const what = series.kind === "bill" ? "bill" : "subscription";
  const occurrences = (detail?.occurrences ?? []).slice(-18);
  const delta = Math.abs(tx.amount) - series.average_amount;
  const priceNote = series.includes_transaction && Math.abs(delta) >= 0.01
    ? `${formatCurrency(Math.abs(delta))} ${delta > 0 ? "more" : "less"} than its usual ${formatCurrency(series.average_amount)}.`
    : null;
  const nextIn = series.next_expected_date ? daysBetween(new Date().toISOString().slice(0, 10), series.next_expected_date) : null;

  return (
    <Section
      id="recurrence"
      eyebrow={`${series.kind === "bill" ? "Bill" : "Subscription"} · ${series.name}`}
      headline={
        series.status === "suggested"
          ? <>Fin thinks this is a {what}, charged {series.cadence_description.toLowerCase()}.</>
          : series.includes_transaction
            ? <>One payment of {series.name}, charged {series.cadence_description.toLowerCase()}.</>
            : <>{series.name} is tracked as a {what}, charged {series.cadence_description.toLowerCase()}.</>
      }
      aside={<Badge variant={badge.variant}>{badge.label}</Badge>}
    >
      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
        <Fact label="Usually" value={formatCurrency(series.average_amount)} />
        <Fact label="Per year" value={formatCurrency(series.annual_equivalent)} />
        <Fact
          label="Next expected"
          value={series.next_expected_date
            ? `${formatDate(series.next_expected_date)}${nextIn != null && nextIn >= 0 && nextIn <= 45 ? ` · in ${nextIn}d` : ""}`
            : "—"}
        />
      </dl>
      {priceNote && <p className="text-xs text-warning">This charge was {priceNote}</p>}
      {occurrences.length > 0 && (
        <div className="flex items-center gap-3">
          <OccurrenceDots occurrences={occurrences} />
          <span className="text-caption text-muted-foreground">last {occurrences.length} expected charges</span>
        </div>
      )}
      <div className="flex flex-wrap items-center gap-2">
        {series.status === "suggested" && (
          <>
            <Button size="sm" variant="outline" onClick={() => lifecycle.mutate("dismiss")} disabled={lifecycle.isPending}>
              Not a subscription
            </Button>
            <Button size="sm" onClick={() => lifecycle.mutate("accept")} disabled={lifecycle.isPending}>
              Track it
            </Button>
          </>
        )}
        <Button size="sm" variant="ghost" onClick={onManage}>Manage {what}</Button>
      </div>
    </Section>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="font-medium tabular-nums">{value}</dd>
    </div>
  );
}
