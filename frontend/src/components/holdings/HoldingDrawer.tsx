import { useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowUpRight, X } from "lucide-react";
import { api } from "@/api/client";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/toast";
import { useDrawerKeyboard } from "@/hooks/useDrawerKeyboard";
import { cn, formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import { holdingDisplayName } from "./types";
import type { HoldingRow } from "./types";
import { invalidate, keys } from "@/api/keys";

interface Props {
  holding: HoldingRow;
  headerHeight?: number;
  onClose: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  onFirst?: () => void;
  onLast?: () => void;
}

export function HoldingDrawer({ holding: h, headerHeight, onClose, onPrev, onNext, onFirst, onLast }: Props) {
  const navigate = useNavigate();
  const qc = useQueryClient();

  const [labelValue, setLabelValue] = useState(h.label ?? "");
  // What we last sent, and for which holding. `h.label` only catches up after
  // the holdings refetch, so comparing against it alone re-sends the same
  // edit: Enter blurs the input, and the blur handler fires a second request
  // that races the first into the unique index. Tagged with the holding id
  // rather than reset during render, which the refs lint rule forbids.
  const committed = useRef<{ id: string; value: string | null }>({ id: h.id, value: h.label ?? null });
  const lastSent = () => (committed.current.id === h.id ? committed.current.value : h.label ?? null);
  // Reset the draft when the drawer switches to another holding
  // (adjust-state-during-render rather than setState in an effect).
  const [prevId, setPrevId] = useState(h.id);
  if (prevId !== h.id) {
    setPrevId(h.id);
    setLabelValue(h.label ?? "");
  }

  const saveLabel = useMutation({
    mutationFn: (label: string | null) =>
      api.patch<{ security_id: string; label: string | null }>(
        `/security_labels/${h.security_id}`,
        { label: label ?? "" }
      ),
    // Labels are embedded in the cached holdings payloads, so every list that
    // can render this row has to refetch.
    onSuccess: () => {
      invalidate(qc, keys.portfolio, keys.crypto, keys.accounts, keys.costBasis);
    },
    // The edit never landed, so let the next blur retry it.
    onError: () => { committed.current = { id: h.id, value: h.label ?? null }; },
  });

  function commitLabel() {
    const next = labelValue.trim() || null;
    if (next === lastSent()) return;
    // A payload cached before security_id existed would otherwise PATCH
    // /security_labels/undefined and surface as a 404 about the security.
    if (!h.security_id) {
      toast.error("This holding is out of date — reload the page to set a label.");
      return;
    }
    committed.current = { id: h.id, value: next };
    saveLabel.mutate(next);
  }

  useDrawerKeyboard({ onClose, onPrev, onNext, onFirst, onLast });

  const gainPositive = h.unrealized_gl >= 0;

  return (
    <div className="flex h-full w-80 flex-col bg-card">
      <div
        data-sidebar
        className="flex items-center justify-between border-b bg-card px-3 text-card-foreground"
        style={headerHeight ? { height: headerHeight } : undefined}
      >
        <div className="flex items-center gap-1.5">
          <p className="text-xs font-medium">Holding</p>
          {h.ticker && (
            <button
              onClick={() => { onClose(); navigate(`/market/${h.ticker}`); }}
              className="rounded p-0.5 text-muted-foreground hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              title="Open security page"
              aria-label="Open security page"
            >
              <ArrowUpRight size={14} />
            </button>
          )}
        </div>
        <button
          onClick={onClose}
          className="rounded p-0.5 hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          aria-label="Close"
        >
          <X size={15} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Market value */}
        <div className="rounded-xl border p-4 text-center">
          <p className="truncate text-sm font-medium">{holdingDisplayName(h) ?? "—"}</p>
          <p className="mt-1 text-2xl font-semibold tabular-nums">{formatCurrency(h.market_value)}</p>
          <p className={cn("mt-0.5 text-xs tabular-nums", moneyColor(h.unrealized_gl) || "text-positive")}>
            {gainPositive ? "+" : ""}{formatCurrency(h.unrealized_gl)} ({gainPositive ? "+" : ""}
            {h.unrealized_gl_pct.toFixed(2)}%)
          </p>
        </div>

        {/* Label — saves on blur */}
        <div className="space-y-1.5">
          <label htmlFor="holding-label" className="text-xs text-muted-foreground">
            Label
          </label>
          <Input
            id="holding-label"
            value={labelValue}
            onChange={(e) => setLabelValue(e.target.value)}
            onBlur={commitLabel}
            onKeyDown={(e) => {
              if (e.key === "Enter") { commitLabel(); e.currentTarget.blur(); }
              // Restore the last value we sent, not h.label — the holdings
              // refetch may not have caught up with an in-flight save yet.
              if (e.key === "Escape") { setLabelValue(lastSent() ?? ""); e.currentTarget.blur(); }
            }}
            placeholder={h.ticker ?? h.name ?? "Name this holding…"}
            className="h-8"
          />
          <p className="text-xs text-muted-foreground">
            Shown instead of the ticker across your holdings. Clear it to fall back to
            the ticker, then the description.
          </p>
        </div>

        <dl className="space-y-3 border-t pt-3 text-sm">
          <Field label="Ticker" value={h.ticker} />
          <Field label="CUSIP" value={h.cusip} mono />
          <Field label="Description" value={h.name} />
          <Field label="Asset class" value={h.asset_class} />
        </dl>

        <dl className="space-y-3 border-t pt-3 text-sm">
          <Field label="Quantity" value={h.quantity.toLocaleString(undefined, { maximumFractionDigits: 8 })} />
          <Field label="Price" value={formatCurrency(h.price)} />
          <Field label="Cost basis" value={h.cost_basis != null ? formatCurrency(h.cost_basis) : null} />
          <Field
            label="Est. annual income"
            value={h.est_annual_income != null ? formatCurrency(h.est_annual_income) : null}
          />
          <Field label="Yield" value={h.dividend_yield != null ? `${h.dividend_yield.toFixed(2)}%` : null} />
          <Field label="As of" value={h.as_of_date ? formatDate(h.as_of_date) : null} />
        </dl>
      </div>
    </div>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function Field({ label, value, mono }: { label: string; value: string | null; mono?: boolean }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="shrink-0 text-muted-foreground">{label}</dt>
      <dd className={cn("truncate text-right font-medium", mono && "font-mono text-xs")}>
        {value || <span className="text-muted-foreground">—</span>}
      </dd>
    </div>
  );
}
