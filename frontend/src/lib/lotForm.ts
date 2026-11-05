import type { CostBasisLot } from "@/api/types";

// ── Investment-lot form state ─────────────────────────────────────────────────

export interface LotFormState {
  account_id: string;
  acquired_date: string;
  quantity: string;
  cost_basis: string;
  notes: string;
}

export function emptyForm(): LotFormState {
  return { account_id: "", acquired_date: "", quantity: "", cost_basis: "", notes: "" };
}

export function lotToForm(lot: CostBasisLot): LotFormState {
  return {
    account_id:    lot.account_id ?? "",
    acquired_date: lot.acquired_date ?? "",
    quantity:      lot.quantity.toString(),
    cost_basis:    lot.cost_basis.toString(),
    notes:         lot.notes ?? "",
  };
}

export function parseDecimal(s: string): number | null {
  const v = parseFloat(s.replace(/[$,]/g, ""));
  return isNaN(v) ? null : v;
}
