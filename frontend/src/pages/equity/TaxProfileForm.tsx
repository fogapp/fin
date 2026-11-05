import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldError } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import { MODELED_STATE, NO_INCOME_TAX_STATES, US_STATES } from "@/lib/usStates";
import type { TaxProfile } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// Per-year household tax profile — the inputs the exercise planner's federal
// and California engines need, plus the state of residence. Only California
// is estimated; any other state's tax is entered here (and an entered amount
// overrides the California estimate too). Deliberately small: the dominant
// error source in any AMT estimate is the income projection, not the
// parameter tables.

export function TaxProfileForm({ profile, onSaved, onCancel }: {
  profile: TaxProfile;
  onSaved: () => void;
  onCancel?: () => void;
}) {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    filing_status: profile.filing_status,
    state: profile.state,
    projected_state_tax: profile.projected_state_tax ?? "",
    projected_wages: profile.projected_wages || "",
    other_ordinary_income: profile.other_ordinary_income || "",
    ltcg_qd_income: profile.ltcg_qd_income || "",
    itemizing: profile.itemizing,
    salt_paid: profile.salt_paid || "",
    itemized_other: profile.itemized_other || "",
    prior_year_total_tax: profile.prior_year_total_tax ?? "",
    prior_year_agi: profile.prior_year_agi ?? "",
    ytd_withholding_federal: profile.ytd_withholding_federal || "",
  });
  const [error, setError] = useState("");

  const num = (v: string | number) => (v === "" ? 0 : Number(v));
  const numOrNull = (v: string | number) => (v === "" ? null : Number(v));

  const save = useMutation({
    mutationFn: () =>
      api.put<TaxProfile>("/tax_profile", {
        tax_year: profile.tax_year,
        filing_status: form.filing_status,
        state: form.state,
        projected_state_tax: numOrNull(form.projected_state_tax),
        projected_wages: num(form.projected_wages),
        other_ordinary_income: num(form.other_ordinary_income),
        ltcg_qd_income: num(form.ltcg_qd_income),
        itemizing: form.itemizing,
        salt_paid: num(form.salt_paid),
        itemized_other: num(form.itemized_other),
        prior_year_total_tax: numOrNull(form.prior_year_total_tax),
        prior_year_agi: numOrNull(form.prior_year_agi),
        ytd_withholding_federal: num(form.ytd_withholding_federal),
      }),
    onSuccess: () => {
      invalidate(qc, keys.taxProfile);
      toast.success("Tax profile saved");
      onSaved();
    },
    onError: (err: Error) => setError(err.message),
  });

  // Blank is fine where Fin knows the answer: the CA estimate or $0.
  const stateTaxRequired =
    form.state !== MODELED_STATE && !NO_INCOME_TAX_STATES.has(form.state) && form.projected_state_tax === "";

  const set = <K extends keyof typeof form>(key: K) => (value: typeof form[K]) =>
    setForm((f) => ({ ...f, [key]: value }));

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Field label="Filing status" htmlFor="tp-status">
          <Select id="tp-status" value={form.filing_status} onChange={(e) => set("filing_status")(e.target.value as "single" | "mfj")}>
            <option value="single">Single</option>
            <option value="mfj">Married filing jointly</option>
          </Select>
        </Field>
        <Field label={`Projected ${profile.tax_year} wages`} required htmlFor="tp-wages">
          <Input id="tp-wages" type="number" min="0" value={form.projected_wages} onChange={(e) => set("projected_wages")(e.target.value)} className="tabular-nums" />
        </Field>
        <Field label="Other ordinary income" htmlFor="tp-other">
          <Input id="tp-other" type="number" value={form.other_ordinary_income} onChange={(e) => set("other_ordinary_income")(e.target.value)} className="tabular-nums" />
        </Field>
        <Field label="LTCG + qualified dividends" htmlFor="tp-ltcg">
          <Input id="tp-ltcg" type="number" value={form.ltcg_qd_income} onChange={(e) => set("ltcg_qd_income")(e.target.value)} className="tabular-nums" />
        </Field>
        <Field label="State of residence" htmlFor="tp-state">
          <Select id="tp-state" value={form.state} onChange={(e) => set("state")(e.target.value)}>
            {US_STATES.map(([code, name]) => <option key={code} value={code}>{name}</option>)}
          </Select>
        </Field>
        <Field label="Projected state tax" required={stateTaxRequired} htmlFor="tp-state-tax">
          <Input
            id="tp-state-tax"
            type="number"
            min="0"
            value={form.projected_state_tax}
            onChange={(e) => set("projected_state_tax")(e.target.value)}
            className="tabular-nums"
            placeholder={
              form.state === MODELED_STATE ? "Blank = Fin's estimate"
              : NO_INCOME_TAX_STATES.has(form.state) ? "Blank = $0"
              : "Required"
            }
          />
        </Field>
        <Field label="Prior-year total tax" htmlFor="tp-prior-tax">
          <Input id="tp-prior-tax" type="number" value={form.prior_year_total_tax} onChange={(e) => set("prior_year_total_tax")(e.target.value)} className="tabular-nums" placeholder="1040 line 24" />
        </Field>
        <Field label="Prior-year AGI" htmlFor="tp-prior-agi">
          <Input id="tp-prior-agi" type="number" value={form.prior_year_agi} onChange={(e) => set("prior_year_agi")(e.target.value)} className="tabular-nums" />
        </Field>
        <Field label="YTD federal withholding" htmlFor="tp-withholding">
          <Input id="tp-withholding" type="number" value={form.ytd_withholding_federal} onChange={(e) => set("ytd_withholding_federal")(e.target.value)} className="tabular-nums" />
        </Field>
      </div>

      <div className="space-y-2">
        <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
          <Checkbox checked={form.itemizing} onChange={(e) => set("itemizing")(e.target.checked)} />
          Itemizing deductions
        </label>
        {form.itemizing && (
          <div className="grid grid-cols-2 gap-3">
            <Field label="State/local taxes paid (SALT)" htmlFor="tp-salt">
              <Input id="tp-salt" type="number" min="0" value={form.salt_paid} onChange={(e) => set("salt_paid")(e.target.value)} className="tabular-nums" />
            </Field>
            <Field label="Other itemized deductions" htmlFor="tp-itemized-other">
              <Input id="tp-itemized-other" type="number" min="0" value={form.itemized_other} onChange={(e) => set("itemized_other")(e.target.value)} className="tabular-nums" />
            </Field>
          </div>
        )}
      </div>

      <FieldError>{error}</FieldError>

      <div className="flex justify-end gap-2">
        {onCancel && <Button variant="outline" size="sm" onClick={onCancel} disabled={save.isPending}>Cancel</Button>}
        <Button size="sm" onClick={() => save.mutate()} disabled={save.isPending || num(form.projected_wages) <= 0 || stateTaxRequired}>
          {save.isPending ? "Saving…" : "Save profile"}
        </Button>
      </div>
    </div>
  );
}
