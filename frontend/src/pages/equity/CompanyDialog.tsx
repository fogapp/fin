import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { FormDialog } from "@/components/ui/form-dialog";
import { Checkbox } from "@/components/ui/checkbox";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import type { EquityCompany } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// Create/edit an equity company. Public companies link to a market security by
// ticker (prices come from quotes); private companies are valued by their FMV
// (409A) history, so creation asks for the first FMV entry.

export function CompanyDialog({ company, onClose }: {
  company?: EquityCompany;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const editing = !!company;

  const [name, setName] = useState(company?.name ?? "");
  const [isPublic, setIsPublic] = useState(company?.public_company ?? false);
  const [ticker, setTicker] = useState(company?.ticker ?? "");
  const [cCorp, setCCorp] = useState(company?.c_corp ?? true);
  const [qsbs, setQsbs] = useState(company?.qsbs_candidate ?? false);
  const [notes, setNotes] = useState(company?.notes ?? "");
  const [fmvPrice, setFmvPrice] = useState("");
  const [fmvDate, setFmvDate] = useState("");
  const [fmvSource, setFmvSource] = useState("409a");
  const [error, setError] = useState("");

  const save = useMutation({
    mutationFn: () => {
      const payload: Record<string, unknown> = {
        name: name.trim(),
        public_company: isPublic,
        ticker: isPublic && ticker.trim() ? ticker.trim().toUpperCase() : null,
        c_corp: cCorp,
        qsbs_candidate: qsbs,
        notes: notes.trim() || null,
      };
      if (!editing && fmvPrice) {
        payload.initial_fmv = {
          price_per_share: Number(fmvPrice),
          effective_date: fmvDate,
          source: fmvSource,
        };
      }
      return editing
        ? api.patch(`/equity/companies/${company.id}`, payload)
        : api.post("/equity/companies", payload);
    },
    onSuccess: () => {
      invalidate(qc, keys.equity);
      toast.success(editing ? "Company updated" : "Company added");
      onClose();
    },
    onError: (err: Error) => setError(err.message),
  });

  const canSave = name.trim().length > 0 && (!fmvPrice || !!fmvDate) && !save.isPending;

  return (
    <FormDialog
      title={editing ? "Edit company" : "Add company"}
      size="md"
      onClose={onClose}
      onSubmit={() => save.mutate()}
      canSubmit={canSave}
      isPending={save.isPending}
      error={error}
      submitLabel={editing ? "Save changes" : "Add company"}
    >
      <Field label="Company name" required htmlFor="eq-company-name">
        <Input id="eq-company-name" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
      </Field>

      <div className="flex flex-wrap gap-x-6 gap-y-2">
        <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
          <Checkbox checked={isPublic} onChange={(e) => setIsPublic(e.target.checked)} />
          Publicly traded
        </label>
        <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
          <Checkbox checked={cCorp} onChange={(e) => setCCorp(e.target.checked)} />
          C-corp
        </label>
        <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
          <Checkbox checked={qsbs} onChange={(e) => setQsbs(e.target.checked)} />
          QSBS candidate
        </label>
      </div>

      {isPublic && (
        <Field label="Ticker" htmlFor="eq-company-ticker">
          <Input
            id="eq-company-ticker"
            value={ticker}
            onChange={(e) => setTicker(e.target.value)}
            placeholder="e.g. MSFT — links market prices"
            className="uppercase"
          />
        </Field>
      )}

      {!isPublic && !editing && (
        <div className="space-y-2 rounded-lg border bg-muted/30 p-3">
          <p className="text-xs font-medium text-muted-foreground">
            Latest 409A / share value (optional — you can add it later)
          </p>
          <div className="grid grid-cols-3 gap-2">
            <Field label="Price per share" htmlFor="eq-fmv-price">
              <Input
                id="eq-fmv-price"
                type="number"
                step="any"
                min="0"
                value={fmvPrice}
                onChange={(e) => setFmvPrice(e.target.value)}
                className="tabular-nums"
              />
            </Field>
            <Field label="Effective date" htmlFor="eq-fmv-date">
              <Input id="eq-fmv-date" type="date" value={fmvDate} onChange={(e) => setFmvDate(e.target.value)} />
            </Field>
            <Field label="Source" htmlFor="eq-fmv-source">
              <Select id="eq-fmv-source" value={fmvSource} onChange={(e) => setFmvSource(e.target.value)}>
                <option value="409a">409A</option>
                <option value="round">Priced round</option>
                <option value="tender">Tender offer</option>
                <option value="manual">Manual</option>
              </Select>
            </Field>
          </div>
        </div>
      )}

      <Field label="Notes" htmlFor="eq-company-notes">
        <Input id="eq-company-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
      </Field>
    </FormDialog>
  );
}
