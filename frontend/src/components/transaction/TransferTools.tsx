import { useState } from "react";
import { ArrowRight, ArrowLeftRight, CreditCard, Clock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { QuickAutomationModal } from "@/components/QuickAutomationModal";
import { LinkTransferModal } from "@/components/LinkTransferModal";
import { formatCurrency } from "@/lib/utils";
import { paymentSettlementStatus } from "@/lib/transactions";
import { useTransactionMutations } from "@/hooks/mutations/useTransactionMutations";
import { useTransferState } from "./useTransferState";
import type { CashTransaction } from "@/api/types";

/**
 * Everything about a row being money moving between accounts rather than
 * spending: the settlement state of a one-sided card payment, the buttons
 * that link it, the linked transfer's treatment, and a detected candidate to
 * confirm. Shared by the transaction drawer and the detail page.
 */
export function TransferTools({ tx }: { tx: CashTransaction }) {
  const { relatedTransfer, pendingTransfer, linkedTransfer } = useTransferState(tx);
  const settlementStatus = paymentSettlementStatus(tx);
  const { confirmTransfer, toggleIncludeInSpend, unlinkTransfer } = useTransactionMutations(tx.id);

  const [transferModal, setTransferModal] = useState<"transfer" | "credit_card_payment" | null>(null);
  // Set after a one-sided transfer link with "always do this" checked; opens
  // QuickAutomationModal prefilled with a transfer_to_account action.
  const [transferAutomation, setTransferAutomation] = useState<{ id: string; name: string } | null>(null);
  const [prevTxId, setPrevTxId] = useState(tx.id);
  if (prevTxId !== tx.id) {
    setPrevTxId(tx.id);
    setTransferModal(null);
    setTransferAutomation(null);
  }

  return (
    <>
      {/* One-sided card payment credit — the bank leg links automatically
          once it posts; explain the state instead of showing nothing. */}
      {!relatedTransfer && settlementStatus && (
        <div className="space-y-2">
          <p className="text-xs font-medium text-muted-foreground">Card payment</p>
          <div className="rounded-lg border bg-muted/30 p-3 space-y-2">
            <div className="flex items-start gap-2 text-xs text-muted-foreground">
              <Clock size={13} className="mt-0.5 shrink-0" />
              <p>
                {settlementStatus === "awaiting"
                  ? "Awaiting settlement — the withdrawal from the paying account usually posts within a few days and links automatically."
                  : "No matching withdrawal found — the account that paid this card may not be tracked in Fin."}
              </p>
            </div>
            <Button
              size="xs"
              variant="outline"
              onClick={() => setTransferModal("credit_card_payment")}
              className="w-full"
            >
              <CreditCard size={12} />
              Link payment source
            </Button>
          </div>
        </div>
      )}

      {/* Transfer section. The payment path is offered from either leg:
          a bank debit picks the card it paid; a card credit picks the
          account that paid it (the settlement card above already covers
          credits that read as payments). */}
      {!pendingTransfer && !tx.transfer_id && (
        <div className="space-y-1.5">
          {(tx.amount < 0 || (tx.source === "credit_card" && !settlementStatus)) && (
            <Button
              size="xs"
              variant="outline"
              onClick={() => setTransferModal("credit_card_payment")}
              className="w-full"
            >
              <CreditCard size={12} />
              Mark as credit card payment
            </Button>
          )}
          <Button
            size="xs"
            variant="outline"
            onClick={() => setTransferModal("transfer")}
            className="w-full"
          >
            <ArrowLeftRight size={12} />
            Link as transfer
          </Button>
        </div>
      )}

      {transferModal && (
        <LinkTransferModal
          tx={tx}
          mode={transferModal}
          onClose={() => setTransferModal(null)}
          onCreateAutomation={(account) => {
            setTransferModal(null);
            setTransferAutomation(account);
          }}
        />
      )}

      {transferAutomation && (
        <QuickAutomationModal
          tx={tx}
          transferAccount={transferAutomation}
          onClose={() => setTransferAutomation(null)}
        />
      )}

      {/* Linked transfer/payment — identity, provenance, treatment */}
      {linkedTransfer && (
        <div className="space-y-2">
          <p className="text-xs font-medium text-muted-foreground">
            {linkedTransfer.kind === "credit_card_payment"
              ? "Card payment"
              : linkedTransfer.kind === "loan_payment"
                ? "Loan payment"
                : "Transfer"}
          </p>
          <div className="rounded-lg border bg-muted/30 p-3 space-y-2">
            <div className="flex items-center gap-2 text-xs">
              <span className="truncate text-muted-foreground">
                {linkedTransfer.from_transaction_id === tx.id
                  ? tx.description
                  : linkedTransfer.from_description ?? linkedTransfer.counterparty_account_name ?? "—"}
              </span>
              <ArrowRight size={11} className="shrink-0 text-muted-foreground" />
              <span className="truncate text-muted-foreground">
                {linkedTransfer.to_transaction_id === tx.id
                  ? tx.description
                  : linkedTransfer.to_description ?? linkedTransfer.counterparty_account_name ?? "—"}
              </span>
            </div>
            <p className="text-xs text-muted-foreground">
              {tx.amount < 0
                ? linkedTransfer.include_in_spend
                  ? "Counted in spending"
                  : "Not counted in spending"
                : "Not counted in income"}
              {linkedTransfer.confirmation_source === "auto" && " · auto-matched"}
              {linkedTransfer.confirmation_source === "workflow" && " · via workflow"}
            </p>
            <div className="flex items-center gap-2">
              {tx.amount < 0 && (
                <Button
                  size="xs"
                  variant="outline"
                  onClick={() => toggleIncludeInSpend.mutate({
                    id: linkedTransfer.id,
                    include_in_spend: !linkedTransfer.include_in_spend,
                  })}
                  disabled={toggleIncludeInSpend.isPending}
                >
                  {linkedTransfer.include_in_spend ? "Exclude from spending" : "Count as spending"}
                </Button>
              )}
              <Button
                size="xs"
                variant="ghost"
                className="ml-auto text-muted-foreground"
                onClick={() => unlinkTransfer.mutate(linkedTransfer.id)}
                disabled={unlinkTransfer.isPending}
              >
                Unlink
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Pending transfer candidate */}
      {pendingTransfer && (
        <div className="space-y-2">
          <p className="text-xs font-medium text-muted-foreground">
            {pendingTransfer.kind === "credit_card_payment"
              ? "Detected card payment"
              : pendingTransfer.kind === "loan_payment"
                ? "Detected loan payment"
                : "Detected transfer"}
          </p>
          <div className="rounded-lg border bg-muted/30 p-3 space-y-2">
            <div className="flex items-center gap-2 text-xs">
              <span className="truncate text-muted-foreground">
                {pendingTransfer.from_description ?? "—"}
              </span>
              <ArrowRight size={11} className="shrink-0 text-muted-foreground" />
              <span className="truncate text-muted-foreground">
                {pendingTransfer.to_description ?? "—"}
              </span>
            </div>
            <div className="flex items-center justify-between gap-2">
              <span className="text-xs font-medium">
                {pendingTransfer.amount != null ? formatCurrency(pendingTransfer.amount) : ""}
              </span>
              {pendingTransfer.date_diff != null && pendingTransfer.date_diff > 0 && (
                <span className="text-tiny text-muted-foreground">{pendingTransfer.date_diff}d apart</span>
              )}
              <Button
                size="xs"
                onClick={() => confirmTransfer.mutate(pendingTransfer.id)}
                disabled={confirmTransfer.isPending}
                className="ml-auto"
              >
                {confirmTransfer.isPending ? "Confirming…" : "Confirm transfer"}
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
