import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { FormDialog } from "@/components/ui/form-dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import { invalidate, keys } from "@/api/keys";

// Record an estimated tax payment — the IRS sends no statement during the
// year; this ledger is what April reconciliation (and the safe-harbor math)
// runs on.

export function PaymentDialog({ taxYear, stateName, onClose }: { taxYear: number; stateName?: string; onClose: () => void }) {
  const qc = useQueryClient();
  const [jurisdiction, setJurisdiction] = useState("federal");
  const [paidOn, setPaidOn] = useState("");
  const [amount, setAmount] = useState("");
  const [notes, setNotes] = useState("");
  const [error, setError] = useState("");

  const save = useMutation({
    mutationFn: () =>
      api.post("/tax/estimated_payments", {
        tax_year: taxYear,
        jurisdiction,
        paid_on: paidOn,
        amount: Number(amount),
        notes: notes.trim() || null,
      }),
    onSuccess: () => {
      invalidate(qc, keys.taxReport);
      toast.success("Payment recorded");
      onClose();
    },
    onError: (err: Error) => setError(err.message),
  });

  const canSave = !save.isPending && paidOn !== "" && Number(amount) > 0;

  return (
    <FormDialog
      title={`Record estimated payment — ${taxYear}`}
      size="sm"
      onClose={onClose}
      onSubmit={() => save.mutate()}
      canSubmit={canSave}
      isPending={save.isPending}
      error={error}
      submitLabel="Record payment"
    >
      <Field label="Jurisdiction" htmlFor="tx-pay-jur">
        <Select id="tx-pay-jur" value={jurisdiction} onChange={(e) => setJurisdiction(e.target.value)}>
          <option value="federal">Federal (IRS)</option>
          <option value="state">{stateName ?? "State"}</option>
        </Select>
      </Field>
      <Field label="Paid on" required htmlFor="tx-pay-date">
        <Input id="tx-pay-date" type="date" value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
      </Field>
      <Field label="Amount" required htmlFor="tx-pay-amount">
        <Input id="tx-pay-amount" type="number" step="any" min="0" value={amount} onChange={(e) => setAmount(e.target.value)} className="tabular-nums" />
      </Field>
      <Field label="Notes" htmlFor="tx-pay-notes">
        <Input id="tx-pay-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="e.g. Q2 voucher" />
      </Field>
    </FormDialog>
  );
}
