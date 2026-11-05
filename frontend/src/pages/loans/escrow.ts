/** Monthly amounts a lender collects into escrow alongside the payment. */
export const ESCROW_FIELDS = [
  { key: "escrow_property_tax", label: "Property taxes", paidKey: "property_tax_paid" },
  { key: "escrow_insurance",    label: "Insurance",      paidKey: "insurance_paid" },
  { key: "escrow_other",        label: "Other escrow",   paidKey: "other_escrow_paid" },
] as const;

export type EscrowField = (typeof ESCROW_FIELDS)[number]["key"];

/** Blank means "not set" rather than zero. */
export function parseOptionalAmount(value: string): number | null {
  return value.trim() === "" ? null : parseFloat(value);
}
