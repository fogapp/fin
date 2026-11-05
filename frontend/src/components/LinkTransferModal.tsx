import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowLeftRight, Check, CreditCard } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { cn, formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import { Dialog, DialogContent, DialogHeader, DialogFooter } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { SkeletonList } from "@/components/ui/skeleton";
import { AccountCombobox } from "@/components/AccountCombobox";
import type { Account, CashTransaction } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Link as transfer ──────────────────────────────────────────────────────────
// One modal for every "this is a transfer, not spending" scenario:
//
//   1. A matching counterpart transaction exists → pick it (creates a real
//      pair — the best representation; future ones are auto-detected).
//   2. The other side is a tracked account with no matchable transaction, or
//      an account we don't sync at all → pick (or create) the account, which
//      records a one-sided transfer with that counterparty.
//
// The account path also offers "always do this", handing off to the
// QuickAutomationModal prefilled with a transfer_to_account action — the same
// learn-from-this-transaction flow used for merchants.

type Selection =
  | { type: "transaction"; id: string }
  | { type: "account"; id: string }
  | null;

function isCryptoAccount(a: Account): boolean {
  return /crypto/i.test(a.account_type ?? "");
}

interface Props {
  tx: CashTransaction;
  onClose: () => void;
  /** Called after a one-sided link when "always do this" was checked. */
  onCreateAutomation?: (account: { id: string; name: string }) => void;
  /**
   * "credit_card_payment" scopes the account picker to Credit Card accounts,
   * adjusts copy, and forces `kind: "credit_card_payment"` on submit — an
   * explicit override for payments PaymentMatcher didn't auto-detect (e.g. a
   * Zelle/ACH payment, or a counterparty account not typed "Credit Card").
   * Default "transfer" is the generic link-any-two-transactions flow.
   */
  mode?: "transfer" | "credit_card_payment";
}

export function LinkTransferModal({ tx, onClose, onCreateAutomation, mode = "transfer" }: Props) {
  const qc = useQueryClient();
  const outflow = tx.amount < 0;
  const isPayment = mode === "credit_card_payment";

  const [selection, setSelection] = useState<Selection>(null);
  const [filter, setFilter] = useState("");
  const [automate, setAutomate] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { data: candidates = [], isPending: searching } = useQuery({
    ...queries.transferSearch(tx.id),
    enabled: true,
  });
  const { data: allAccounts = [] } = useQuery(queries.accounts());
  // Payment mode works from either leg: the bank debit picks the card it paid
  // off; the card credit picks the account that funded it. Crypto wallets
  // (a Coinbase sync creates hundreds) sort last so the bank, card and
  // placeholder accounts a transfer usually involves come first.
  const accounts = (isPayment
    ? allAccounts.filter((a) => (a.account_type === "Credit Card") === outflow)
    : allAccounts
  ).slice().sort((a, b) => Number(isCryptoAccount(a)) - Number(isCryptoAccount(b)));

  const selectedAccount =
    selection?.type === "account" ? allAccounts.find((a) => a.id === selection.id) ?? null : null;

  const link = useMutation({
    mutationFn: () => {
      if (selection?.type === "transaction") {
        return api.post("/transfers", {
          from_transaction_id:   outflow ? tx.id : selection.id,
          from_transaction_type: "CashTransaction",
          to_transaction_id:     outflow ? selection.id : tx.id,
          to_transaction_type:   "CashTransaction",
          amount:                Math.abs(tx.amount),
          auto_confirm:          true,
          ...(isPayment && { kind: "credit_card_payment" }),
        });
      }
      // One-sided: this transaction on its sign-appropriate side, the chosen
      // account as counterparty.
      return api.post("/transfers", {
        [outflow ? "from_transaction_id" : "to_transaction_id"]:     tx.id,
        [outflow ? "from_transaction_type" : "to_transaction_type"]: "CashTransaction",
        counterparty_account_id: selection!.id,
        amount:                  Math.abs(tx.amount),
        auto_confirm:            true,
        ...(isPayment && { kind: "credit_card_payment" }),
      });
    },
    onSuccess: async () => {
      await invalidate(qc, keys.cashTransactions, keys.transfers);
      const account = selectedAccount;
      onClose();
      if (automate && account && onCreateAutomation) {
        onCreateAutomation({ id: account.id, name: account.name });
      }
    },
    onError: (err: Error) => setError(err.message),
  });

  const filtered = candidates.filter((c) =>
    filter === "" ||
    (c.description ?? "").toLowerCase().includes(filter.toLowerCase()) ||
    (c.account_name ?? "").toLowerCase().includes(filter.toLowerCase()),
  );

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent size="md">
        <DialogHeader title={isPayment ? "Mark as credit card payment" : "Link as transfer"} />

        <div className="space-y-4 p-5">
          {/* The transaction being linked */}
          <div className="rounded-lg border bg-muted/30 px-3 py-2">
            <div className="flex items-center justify-between gap-2 text-sm">
              <span className="min-w-0 truncate font-medium">{tx.description}</span>
              <span className={cn("shrink-0 font-mono tabular-nums", moneyColor(tx.amount))}>
                {formatCurrency(tx.amount)}
              </span>
            </div>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {tx.account_name ?? "Unknown account"} · {formatDate(tx.transaction_date)}
            </p>
          </div>

          <p className="text-sm font-medium">
            {isPayment
              ? outflow ? "Which credit card did this pay off?" : "Which account paid off this card?"
              : outflow ? "Where did this money go?" : "Where did this money come from?"}
          </p>

          {/* Path 1 — matching counterpart transactions */}
          <div className="space-y-2">
            <div className="flex items-center justify-between gap-2">
              <p className="text-xs font-medium text-muted-foreground">
                Nearby transactions going the other way{!searching && candidates.length > 0 && ` (${candidates.length})`}
              </p>
              {candidates.length > 3 && (
                <Input
                  value={filter}
                  onChange={(e) => setFilter(e.target.value)}
                  placeholder="Filter…"
                  aria-label="Filter matching transactions"
                  className="h-7 w-40 px-2.5 text-xs"
                />
              )}
            </div>

            {searching ? (
              <SkeletonList rows={2} rowClassName="h-9 rounded-lg" />
            ) : candidates.length === 0 ? (
              <p className="text-xs text-muted-foreground">
                Nothing moving the other way within two weeks — the other side isn't in Fin, so link to an account below instead.
              </p>
            ) : (
              <div className="max-h-44 divide-y overflow-y-auto rounded-lg border" role="radiogroup" aria-label="Matching transactions">
                {filtered.map((c) => {
                  const selected = selection?.type === "transaction" && selection.id === c.id;
                  return (
                    <button
                      key={c.id}
                      role="radio"
                      aria-checked={selected}
                      onClick={() => setSelection(selected ? null : { type: "transaction", id: c.id })}
                      className={cn(
                        "flex w-full items-center gap-2 px-3 py-2 text-left text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
                        selected ? "bg-primary/8" : "hover:bg-accent",
                      )}
                    >
                      <Check size={13} className={cn("shrink-0 text-primary", selected ? "opacity-100" : "opacity-0")} />
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">{c.description}</p>
                        <p className="text-muted-foreground">
                          {c.account_name} · {formatDate(c.transaction_date)}
                          {c.date_diff > 0 && ` · ${c.date_diff}d apart`}
                        </p>
                      </div>
                      <div className="flex shrink-0 flex-col items-end">
                        <span className={cn("font-mono tabular-nums", moneyColor(c.amount))}>
                          {formatCurrency(c.amount)}
                        </span>
                        {/* Rows arrive ranked by amount closeness; say why
                            each one is here rather than making the reader
                            compare figures. */}
                        <span className={cn("text-tiny", c.amount_diff === 0 ? "text-positive" : "text-muted-foreground")}>
                          {c.amount_diff === 0 ? "same amount" : `${formatCurrency(c.amount_diff)} off`}
                        </span>
                      </div>
                    </button>
                  );
                })}
                {filtered.length === 0 && (
                  <p className="px-3 py-2 text-xs text-muted-foreground">No matches for the current filter.</p>
                )}
              </div>
            )}
          </div>

          {/* Path 2 — counterparty account (one-sided) */}
          <div className="space-y-2">
            <p className="text-xs font-medium text-muted-foreground">
              {isPayment
                ? outflow ? "Or pick the card" : "Or pick the paying account"
                : `${candidates.length > 0 ? "Or link " : "Link "}${outflow ? "to one of your accounts" : "from one of your accounts"}`}
            </p>
            <AccountCombobox
              value={selection?.type === "account" ? selection.id : ""}
              onChange={(id) => setSelection(id ? { type: "account", id } : null)}
              accounts={accounts}
              excludeIds={tx.account_id ? [tx.account_id] : []}
              placeholder={isPayment
                ? outflow
                  ? 'Search credit cards, or type a name to create one (e.g. "Chase Sapphire")…'
                  : 'Search accounts, or type a name to create one (e.g. "Chase Checking")…'
                : 'Search accounts, or type a name to create one (e.g. "Schwab")…'}
              createDefaults={isPayment ? { account_type: outflow ? "Credit Card" : "Checking" } : undefined}
            />
            <p className="text-xs text-muted-foreground">
              {isPayment
                ? outflow
                  ? "The card doesn't need to be tracked in Fin — a lightweight placeholder works, and this payment will represent its spending."
                  : "The paying account doesn't need to be tracked in Fin — a lightweight placeholder works."
                : <>Transfers move money between <span className="font-medium">your own</span> accounts. Payments to someone else should stay categorized as spending.</>}
            </p>
          </div>

          {/* Learn from this action — only for the account path; paired
              transfers are already caught by the automatic scanner. */}
          {selection?.type === "account" && onCreateAutomation && (
            <label className="flex cursor-pointer select-none items-start gap-2 text-sm">
              <Checkbox
                checked={automate}
                onChange={(e) => setAutomate(e.target.checked)}
                className="mt-0.5"
              />
              <span>
                Always link transactions like this to {selectedAccount?.name ?? "this account"}
                <span className="block text-xs text-muted-foreground">
                  Opens the automation editor so you can review what will match.
                </span>
              </span>
            </label>
          )}

          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={link.isPending}>Cancel</Button>
          <Button onClick={() => link.mutate()} disabled={!selection || link.isPending}>
            {isPayment ? <CreditCard size={14} /> : <ArrowLeftRight size={14} />}
            {link.isPending ? "Linking…" : isPayment ? "Mark as payment" : "Link transfer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
