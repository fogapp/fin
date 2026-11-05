import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { FormDialog } from "@/components/ui/form-dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import type { TaxAdjustment } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// Manual line items — the escape hatch that makes any year representable:
// K-1 income, rental, business income, credits, payroll 401(k) contributions
// Fin can't see, etc.

const BUCKETS = [
  { value: "401k", label: "401(k) employee deferral" },
  { value: "ira", label: "IRA / Roth IRA" },
  { value: "hsa", label: "HSA" },
  { value: "education", label: "529 gifts" },
];

export function AdjustmentDialog({ taxYear, adjustment, onClose }: {
  taxYear: number;
  adjustment?: TaxAdjustment;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const editing = !!adjustment;
  const [kind, setKind] = useState(adjustment?.kind ?? "income");
  const [jurisdiction, setJurisdiction] = useState(adjustment?.jurisdiction ?? "both");
  const [label, setLabel] = useState(adjustment?.label ?? "");
  const [amount, setAmount] = useState(adjustment ? String(adjustment.amount) : "");
  const [bucket, setBucket] = useState(adjustment?.bucket ?? "401k");
  const [notes, setNotes] = useState(adjustment?.notes ?? "");
  const [error, setError] = useState("");

  const save = useMutation({
    mutationFn: () => {
      const payload = {
        tax_year: taxYear,
        kind,
        jurisdiction,
        label: label.trim(),
        amount: Number(amount),
        bucket: kind === "contribution" ? bucket : null,
        notes: notes.trim() || null,
      };
      return editing
        ? api.patch(`/tax/adjustments/${adjustment.id}`, payload)
        : api.post("/tax/adjustments", payload);
    },
    onSuccess: () => {
      invalidate(qc, keys.taxReport);
      toast.success(editing ? "Adjustment updated" : "Adjustment added");
      onClose();
    },
    onError: (err: Error) => setError(err.message),
  });

  const canSave = !save.isPending && label.trim() !== "" && amount !== "" && !Number.isNaN(Number(amount));

  return (
    <FormDialog
      title={editing ? "Edit adjustment" : `Add adjustment — ${taxYear}`}
      size="md"
      onClose={onClose}
      onSubmit={() => save.mutate()}
      canSubmit={canSave}
      isPending={save.isPending}
      error={error}
      submitLabel={editing ? "Save changes" : "Add adjustment"}
    >
      <div className="grid grid-cols-2 gap-3">
        <Field label="Type" htmlFor="tx-adj-kind">
          <Select id="tx-adj-kind" value={kind} onChange={(e) => setKind(e.target.value as TaxAdjustment["kind"])}>
            <option value="income">Income (K-1, rental, business…)</option>
            <option value="deduction">Deduction</option>
            <option value="credit">Credit</option>
            <option value="payment">Payment / withholding</option>
            <option value="contribution">Contribution</option>
          </Select>
        </Field>
        <Field label="Applies to" htmlFor="tx-adj-jur">
          <Select id="tx-adj-jur" value={jurisdiction} onChange={(e) => setJurisdiction(e.target.value as TaxAdjustment["jurisdiction"])}>
            <option value="both">Federal + California</option>
            <option value="federal">Federal only</option>
            <option value="state">California only</option>
          </Select>
        </Field>
        <Field label="Label" required htmlFor="tx-adj-label">
          <Input id="tx-adj-label" value={label} onChange={(e) => setLabel(e.target.value)} placeholder="e.g. K-1 — Fund II" />
        </Field>
        <Field label="Amount" required htmlFor="tx-adj-amount">
          <Input id="tx-adj-amount" type="number" step="any" value={amount} onChange={(e) => setAmount(e.target.value)} className="tabular-nums" />
        </Field>
        {kind === "contribution" && (
          <Field label="Counts toward" htmlFor="tx-adj-bucket">
            <Select id="tx-adj-bucket" value={bucket} onChange={(e) => setBucket(e.target.value)}>
              {BUCKETS.map((b) => <option key={b.value} value={b.value}>{b.label}</option>)}
            </Select>
          </Field>
        )}
      </div>
      <Field label="Notes" htmlFor="tx-adj-notes">
        <Input id="tx-adj-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
      </Field>
    </FormDialog>
  );
}
