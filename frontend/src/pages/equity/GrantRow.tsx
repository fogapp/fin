import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Check, ChevronDown, ChevronRight, Pencil, Trash2 } from "lucide-react";
import { api } from "@/api/client";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { toast } from "@/components/ui/toast";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import type { EquityCompany, EquityGrant } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

const TYPE_LABEL: Record<string, string> = { iso: "ISO", nso: "NSO", rsu: "RSU", rsa: "RSA" };

const EVENT_LABEL: Record<string, string> = {
  exercise: "Exercised",
  settlement: "Settled",
  sale: "Sold",
  cancellation: "Cancelled",
};

export function GrantRow({ grant: g, company, whatIfPrice, onEdit, onRecordEvent, onPlanExercise }: {
  grant: EquityGrant;
  company: EquityCompany;
  /** Optional scenario price overriding the company share price for value display. */
  whatIfPrice: number | null;
  onEdit: () => void;
  onRecordEvent: () => void;
  /** Options only — opens the tax-aware exercise planner. */
  onPlanExercise?: () => void;
}) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const [expanded, setExpanded] = useState(false);

  const destroy = useMutation({
    mutationFn: () => api.delete(`/equity/grants/${g.id}`),
    onSuccess: () => {
      invalidate(qc, keys.equity);
      toast.success("Grant deleted");
    },
  });

  const deleteEvent = useMutation({
    mutationFn: (id: string) => api.delete(`/equity/events/${id}`),
    onSuccess: () => invalidate(qc, keys.equity),
  });

  async function handleDelete() {
    const ok = await confirm({
      title: `Delete grant ${g.label ?? TYPE_LABEL[g.grant_type]}?`,
      description: "Its vesting schedule and recorded events will be removed.",
      confirmLabel: "Delete",
      destructive: true,
    });
    if (ok) destroy.mutate();
  }

  const isOption = g.grant_type === "iso" || g.grant_type === "nso";
  const vestedPct = g.quantity > 0 ? (g.vested_quantity / g.quantity) * 100 : 0;

  // Scenario values: recompute client-side at the what-if price.
  const perShare = (qty: number, price: number) =>
    isOption ? Math.max(price - (g.strike_price ?? 0), 0) * qty : price * qty;
  const vestedValue = whatIfPrice != null ? perShare(g.vested_quantity, whatIfPrice) : g.vested_value;
  const unvestedValue = whatIfPrice != null ? perShare(g.unvested_quantity, whatIfPrice) : g.unvested_value;

  const expired = g.expiration_date != null && g.expiration_date < new Date().toISOString().slice(0, 10);

  return (
    <div className={cn(expanded && "bg-muted/20")}>
      <button
        onClick={() => setExpanded((e) => !e)}
        aria-expanded={expanded}
        className="grid w-full grid-cols-[auto_minmax(0,1.5fr)_1fr_1fr_1fr_1.2fr] items-center gap-3 px-4 py-2.5 text-left text-sm transition-colors hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
      >
        {expanded ? <ChevronDown size={14} className="text-muted-foreground" /> : <ChevronRight size={14} className="text-muted-foreground" />}
        <span className="flex min-w-0 items-center gap-2">
          <Badge variant={isOption ? "default" : "outline"}>{TYPE_LABEL[g.grant_type]}</Badge>
          <span className="truncate font-medium">{g.label ?? formatDate(g.grant_date)}</span>
          {g.double_trigger && <Badge variant="outline">2-trigger</Badge>}
          {expired && <Badge variant="destructive">Expired</Badge>}
        </span>
        <span className="tabular-nums text-muted-foreground">{g.quantity.toLocaleString()}</span>
        <span className="flex items-center gap-2">
          <span className="h-1.5 w-16 overflow-hidden rounded-full bg-muted">
            <span className="block h-full rounded-full bg-primary" style={{ width: `${Math.min(vestedPct, 100)}%` }} />
          </span>
          <span className="tabular-nums text-xs text-muted-foreground">{vestedPct.toFixed(0)}%</span>
        </span>
        <span className="tabular-nums text-muted-foreground">
          {isOption && g.strike_price != null ? formatCurrency(g.strike_price) : "—"}
        </span>
        <span className="text-right tabular-nums font-medium">
          {vestedValue != null ? formatCurrency(vestedValue) : "—"}
          {unvestedValue != null && unvestedValue > 0 && (
            <span className="block text-xs font-normal text-muted-foreground">
              +{formatCurrency(unvestedValue)} unvested
            </span>
          )}
        </span>
      </button>

      {expanded && (
        <div className="grid gap-4 border-t px-4 py-3 md:grid-cols-2">
          {/* Vesting schedule */}
          <div>
            <div className="mb-1.5 flex items-center justify-between">
              <p className="text-xs font-medium text-muted-foreground">Vesting schedule</p>
              {g.next_vest && (
                <p className="text-xs text-muted-foreground">
                  Next: <span className="font-medium text-foreground">{g.next_vest.quantity.toLocaleString()}</span> on {formatDate(g.next_vest.date)}
                </p>
              )}
            </div>
            <div className="max-h-48 overflow-y-auto rounded-lg border bg-card">
              {g.tranches.length === 0 ? (
                <p className="px-3 py-2 text-xs text-muted-foreground">No schedule.</p>
              ) : (
                <table className="w-full text-xs">
                  <tbody className="divide-y">
                    {g.tranches.map((t, i) => (
                      <tr key={i} className={cn(t.vested && "text-muted-foreground")}>
                        <td className="w-6 px-3 py-1.5">
                          <Check size={11} className={cn("text-positive", t.vested ? "opacity-100" : "opacity-0")} />
                        </td>
                        <td className="py-1.5">{formatDate(t.date)}</td>
                        <td className="px-3 py-1.5 text-right tabular-nums">{t.quantity.toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </div>

          {/* Events + actions */}
          <div>
            <div className="mb-1.5 flex items-center justify-between">
              <p className="text-xs font-medium text-muted-foreground">Events</p>
              <div className="flex items-center gap-1">
                {isOption && onPlanExercise && (
                  <Button variant="outline" size="xs" onClick={onPlanExercise}>Plan exercise</Button>
                )}
                <Button variant="ghost" size="xs" onClick={onRecordEvent}>Record event</Button>
                <Button variant="ghost" size="icon-sm" aria-label="Edit grant" onClick={onEdit}>
                  <Pencil size={13} />
                </Button>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  aria-label="Delete grant"
                  onClick={handleDelete}
                  className="text-destructive hover:bg-destructive/10 hover:text-destructive"
                >
                  <Trash2 size={13} />
                </Button>
              </div>
            </div>
            {g.events.length === 0 ? (
              <p className="rounded-lg border bg-card px-3 py-2 text-xs text-muted-foreground">
                No events yet — exercises, settlements, and sales appear here.
              </p>
            ) : (
              <div className="max-h-48 divide-y overflow-y-auto rounded-lg border bg-card text-xs">
                {g.events.map((e) => (
                  <div key={e.id} className="group flex items-center gap-2 px-3 py-1.5">
                    <span className="font-medium">{EVENT_LABEL[e.kind]}</span>
                    <span className="tabular-nums">{e.quantity.toLocaleString()}</span>
                    {e.share_price != null && (
                      <span className="tabular-nums text-muted-foreground">@ {formatCurrency(e.share_price)}</span>
                    )}
                    {e.election_83b && <Badge variant="outline">83(b)</Badge>}
                    <span className="ml-auto text-muted-foreground">{formatDate(e.occurred_on)}</span>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="Delete event"
                      onClick={() => deleteEvent.mutate(e.id)}
                      className="opacity-0 transition-opacity hover:bg-destructive/10 hover:text-destructive focus-visible:opacity-100 group-hover:opacity-100"
                    >
                      <Trash2 size={11} />
                    </Button>
                  </div>
                ))}
              </div>
            )}
            {(g.exercised_quantity > 0 || g.settled_quantity > 0 || g.sold_quantity > 0) && (
              <p className="mt-1.5 text-xs text-muted-foreground">
                {g.exercised_quantity > 0 && <>Exercised {g.exercised_quantity.toLocaleString()} · </>}
                {g.settled_quantity > 0 && <>Settled {g.settled_quantity.toLocaleString()} · </>}
                {g.sold_quantity > 0 && <>Sold {g.sold_quantity.toLocaleString()} · </>}
                {company.name}
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
