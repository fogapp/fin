import { useState } from "react";
import { X, RefreshCw, Check } from "lucide-react";
import { useMutation } from "@tanstack/react-query";
import { useDrawerKeyboard } from "@/hooks/useDrawerKeyboard";
import { Button } from "@/components/ui/button";
import { Drawer, DrawerContent, DrawerHeader } from "@/components/ui/drawer";
import { formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import { api } from "@/api/client";
import type { InvestmentTransaction } from "@/api/types";

const POSITION_CATEGORIES = ["Purchase", "Sale"];

interface Props {
  tx: InvestmentTransaction;
  onClose: () => void;
  onReprocessed?: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  onFirst?: () => void;
  onLast?: () => void;
  /** When true renders inline (no fixed overlay) — used inside split-view tables. */
  inline?: boolean;
}

export function InvestmentTransactionDrawer({ tx, onClose, onReprocessed, onPrev, onNext, onFirst, onLast, inline = false }: Props) {
  useDrawerKeyboard({ onClose, onPrev, onNext, onFirst, onLast });
  const [done, setDone] = useState(false);

  const reprocess = useMutation({
    mutationFn: () => api.post(`/investment_transactions/${tx.id}/reprocess`),
    onSuccess: () => {
      setDone(true);
      onReprocessed?.();
      setTimeout(() => setDone(false), 2500);
    },
  });

  const primaryAmount = tx.amount_usd || tx.cost_usd || tx.income_usd;
  const gl = (tx.gl_short_usd || 0) + (tx.gl_long_usd || 0);
  const canReprocess = tx.transaction_type_category != null && POSITION_CATEGORIES.includes(tx.transaction_type_category);
  const title = `${tx.security_ticker ? `${tx.security_ticker} · ` : ""}${tx.transaction_type ?? "—"}`;

  const body = (
    <>
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        <div className="rounded-xl border p-4 text-center">
          <p className="text-2xl font-semibold tabular-nums">{formatCurrency(Math.abs(primaryAmount))}</p>
          <p className="mt-0.5 text-xs text-muted-foreground">{tx.transaction_type}</p>
        </div>

        <dl className="space-y-3 text-sm">
          {tx.security_name && <Field label="Security" value={tx.security_name} />}
          {tx.security_ticker && <Field label="Ticker" value={tx.security_ticker} />}
          <Field label="Account" value={tx.account_name} />
          <Field label="Trade date" value={formatDate(tx.trade_date)} />
          {tx.description && tx.description !== tx.security_name && (
            <Field label="Description" value={tx.description} />
          )}
          {tx.quantity > 0 && <Field label="Quantity" value={tx.quantity.toLocaleString()} />}
          {tx.price_usd > 0 && <Field label="Price" value={formatCurrency(tx.price_usd)} />}
          {tx.cost_usd !== 0 && <Field label="Cost" value={formatCurrency(Math.abs(tx.cost_usd))} />}
          {tx.income_usd !== 0 && <Field label="Income" value={formatCurrency(tx.income_usd)} />}
          {tx.amount_usd !== 0 && <Field label="Proceeds" value={formatCurrency(tx.amount_usd)} />}
          {gl !== 0 && (
            <div className="flex justify-between gap-4">
              <dt className="text-muted-foreground shrink-0">Realized G/L</dt>
              <dd className={`text-right font-medium ${moneyColor(gl)}`}>
                {formatCurrency(gl)}
                {tx.gl_short_usd !== 0 && tx.gl_long_usd !== 0 && (
                  <span className="block text-xs text-muted-foreground">
                    {formatCurrency(tx.gl_short_usd)} short · {formatCurrency(tx.gl_long_usd)} long
                  </span>
                )}
              </dd>
            </div>
          )}
        </dl>
      </div>

      {canReprocess && (
        <div className="border-t p-4">
          <Button
            variant="outline"
            size="sm"
            onClick={() => reprocess.mutate()}
            disabled={reprocess.isPending || done}
            className="w-full gap-2 text-muted-foreground hover:text-foreground"
          >
            {done
              ? <><Check size={12} /> Holdings updated</>
              : <><RefreshCw size={12} className={reprocess.isPending ? "animate-spin" : ""} /> Update holdings from this transaction</>
            }
          </Button>
        </div>
      )}
    </>
  );

  // In-flow split-view panel — intentionally not the overlay Drawer primitive.
  if (inline) {
    return (
      <div className="flex h-full flex-col border-l bg-card">
        <div data-sidebar className="flex items-center justify-between border-b bg-card px-4 py-3 text-card-foreground">
          <p className="text-sm font-medium">{title}</p>
          <button
            onClick={onClose}
            aria-label="Close"
            className="rounded p-1 hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <X size={15} />
          </button>
        </div>
        {body}
      </div>
    );
  }

  return (
    <Drawer open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DrawerContent className="sm:w-80">
        <DrawerHeader title={title} />
        {body}
      </DrawerContent>
    </Drawer>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-muted-foreground shrink-0">{label}</dt>
      <dd className="text-right font-medium">{value}</dd>
    </div>
  );
}
