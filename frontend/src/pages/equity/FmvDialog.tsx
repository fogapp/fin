import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { FormDialog } from "@/components/ui/form-dialog";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import type { EquityCompany } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// Record a share-value observation for a private company (409A update, priced
// round, tender). Employees can't export FMV history from Carta, so the
// household keeps its own — this is that ledger's entry form.

export function FmvDialog({ company, onClose }: {
  company: EquityCompany;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const [price, setPrice] = useState("");
  const [date, setDate] = useState("");
  const [source, setSource] = useState("409a");
  const [error, setError] = useState("");

  const save = useMutation({
    mutationFn: () =>
      api.post(`/equity/companies/${company.id}/fmv_entries`, {
        price_per_share: Number(price),
        effective_date: date,
        source,
      }),
    onSuccess: () => {
      invalidate(qc, keys.equity);
      toast.success("Share value recorded");
      onClose();
    },
    onError: (err: Error) => setError(err.message),
  });

  const canSave = !save.isPending && Number(price) > 0 && date !== "";

  return (
    <FormDialog
      title={`Record share value — ${company.name}`}
      size="sm"
      onClose={onClose}
      onSubmit={() => save.mutate()}
      canSubmit={canSave}
      isPending={save.isPending}
      error={error}
      submitLabel="Record"
    >
      <Field label="Price per share" required htmlFor="eq-fmv2-price">
        <Input id="eq-fmv2-price" type="number" step="any" min="0" value={price} onChange={(e) => setPrice(e.target.value)} className="tabular-nums" autoFocus />
      </Field>
      <Field label="Effective date" required htmlFor="eq-fmv2-date">
        <Input id="eq-fmv2-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
      </Field>
      <Field label="Source" htmlFor="eq-fmv2-source">
        <Select id="eq-fmv2-source" value={source} onChange={(e) => setSource(e.target.value)}>
          <option value="409a">409A</option>
          <option value="round">Priced round</option>
          <option value="tender">Tender offer</option>
          <option value="manual">Manual</option>
        </Select>
      </Field>
    </FormDialog>
  );
}
