import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import type { CashTransaction } from "@/api/types";

/**
 * The transfer a row belongs to: the linked transfer for confirmed rows and
 * the detected candidate for unlinked ones, plus the other side's account
 * name for a linked one.
 */
export function useTransferState(tx: CashTransaction) {
  const { data: relatedTransfer } = useQuery(queries.pendingTransfer(tx.id, "CashTransaction"));
  const pendingTransfer = relatedTransfer && !relatedTransfer.confirmed_at ? relatedTransfer : null;
  const linkedTransfer = relatedTransfer && tx.transfer_id === relatedTransfer.id ? relatedTransfer : null;
  // Only to name the other side of a linked transfer.
  const { data: accounts = [] } = useQuery({ ...queries.accounts(), enabled: !!tx.transfer_id });
  const counterpartyName = (() => {
    if (!linkedTransfer) return null;
    const otherId = linkedTransfer.to_transaction_id === tx.id
      ? linkedTransfer.from_account_id
      : linkedTransfer.from_transaction_id === tx.id
        ? linkedTransfer.to_account_id
        : null;
    return (otherId && accounts.find((a) => a.id === otherId)?.name) || linkedTransfer.counterparty_account_name || null;
  })();
  return { relatedTransfer, pendingTransfer, linkedTransfer, counterpartyName };
}
