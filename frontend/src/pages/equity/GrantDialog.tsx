import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { FormDialog } from "@/components/ui/form-dialog";
import { Checkbox } from "@/components/ui/checkbox";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import type { EquityCompany, EquityGrant, EquityGrantType } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// Create/edit a grant. Field set mirrors what the equity-comp research found
// to be the validated minimal intake (~9 fields, Secfi's model): type, dates,
// quantity, strike for options, and a flat vesting schedule (interval +
// occurrences + cliff). Custom per-tranche schedules are import/API-only.

const OPTION_TYPES: EquityGrantType[] = ["iso", "nso"];

export function GrantDialog({ company, grant, onClose }: {
  company: EquityCompany;
  grant?: EquityGrant;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const editing = !!grant;

  const [label, setLabel] = useState(grant?.label ?? "");
  const [grantType, setGrantType] = useState<EquityGrantType>(grant?.grant_type ?? "iso");
  const [grantDate, setGrantDate] = useState(grant?.grant_date ?? "");
  const [commencementDate, setCommencementDate] = useState(grant?.vesting_commencement_date ?? "");
  const [quantity, setQuantity] = useState(grant ? String(grant.quantity) : "");
  const [strike, setStrike] = useState(grant?.strike_price != null ? String(grant.strike_price) : "");
  const [interval, setInterval] = useState(grant?.vesting_interval ?? "monthly");
  const [occurrences, setOccurrences] = useState(grant?.vesting_occurrences != null ? String(grant.vesting_occurrences) : "48");
  const [cliff, setCliff] = useState(grant ? String(grant.cliff_installments) : "12");
  const [expiration, setExpiration] = useState(grant?.expiration_date ?? "");
  const [pteDays, setPteDays] = useState(grant?.pte_window_days != null ? String(grant.pte_window_days) : "90");
  const [earlyExercisable, setEarlyExercisable] = useState(grant?.early_exercisable ?? false);
  const [doubleTrigger, setDoubleTrigger] = useState(grant?.double_trigger ?? false);
  const [notes, setNotes] = useState(grant?.notes ?? "");
  const [error, setError] = useState("");

  const isOption = OPTION_TYPES.includes(grantType);
  const hasCustomTranches = !!grant?.custom_tranches?.length;

  const save = useMutation({
    mutationFn: () => {
      const payload: Record<string, unknown> = {
        equity_company_id: company.id,
        label: label.trim() || null,
        grant_type: grantType,
        grant_date: grantDate,
        vesting_commencement_date: commencementDate || null,
        quantity: Number(quantity),
        strike_price: isOption && strike ? Number(strike) : null,
        early_exercisable: isOption ? earlyExercisable : false,
        double_trigger: grantType === "rsu" ? doubleTrigger : false,
        expiration_date: expiration || null,
        pte_window_days: isOption && pteDays ? Number(pteDays) : null,
        notes: notes.trim() || null,
      };
      if (!hasCustomTranches) {
        payload.vesting_interval = interval === "none" ? null : interval;
        payload.vesting_occurrences = interval === "none" ? null : Number(occurrences);
        payload.cliff_installments = interval === "none" ? 0 : Number(cliff || 0);
      }
      return editing
        ? api.patch(`/equity/grants/${grant.id}`, payload)
        : api.post("/equity/grants", payload);
    },
    onSuccess: () => {
      invalidate(qc, keys.equity);
      toast.success(editing ? "Grant updated" : "Grant added");
      onClose();
    },
    onError: (err: Error) => setError(err.message),
  });

  const canSave =
    !save.isPending &&
    grantDate !== "" &&
    Number(quantity) > 0 &&
    (!isOption || strike !== "") &&
    (interval === "none" || hasCustomTranches || Number(occurrences) > 0);

  return (
    <FormDialog
      title={editing ? `Edit grant — ${company.name}` : `Add grant — ${company.name}`}
      size="lg"
      onClose={onClose}
      onSubmit={() => save.mutate()}
      canSubmit={canSave}
      isPending={save.isPending}
      error={error}
      submitLabel={editing ? "Save changes" : "Add grant"}
    >
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Field label="Label" htmlFor="eq-grant-label">
          <Input id="eq-grant-label" value={label} onChange={(e) => setLabel(e.target.value)} placeholder="e.g. ISO-2024-1" autoFocus />
        </Field>
        <Field label="Type" required htmlFor="eq-grant-type">
          <Select id="eq-grant-type" value={grantType} onChange={(e) => setGrantType(e.target.value as EquityGrantType)}>
            <option value="iso">ISO</option>
            <option value="nso">NSO</option>
            <option value="rsu">RSU</option>
            <option value="rsa">RSA</option>
          </Select>
        </Field>
        <Field label="Quantity" required htmlFor="eq-grant-qty">
          <Input id="eq-grant-qty" type="number" step="any" min="0" value={quantity} onChange={(e) => setQuantity(e.target.value)} className="tabular-nums" />
        </Field>
        <Field label="Grant date" required htmlFor="eq-grant-date">
          <Input id="eq-grant-date" type="date" value={grantDate} onChange={(e) => setGrantDate(e.target.value)} />
        </Field>
        <Field label="Vesting starts" htmlFor="eq-grant-commence">
          <Input
            id="eq-grant-commence"
            type="date"
            value={commencementDate}
            onChange={(e) => setCommencementDate(e.target.value)}
            placeholder={grantDate}
          />
        </Field>
        {isOption && (
          <Field label="Strike price" required htmlFor="eq-grant-strike">
            <Input id="eq-grant-strike" type="number" step="any" min="0" value={strike} onChange={(e) => setStrike(e.target.value)} className="tabular-nums" />
          </Field>
        )}
      </div>

      {/* Vesting schedule */}
      {hasCustomTranches ? (
        <p className="rounded-lg border bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
          This grant uses a custom per-tranche schedule ({grant?.custom_tranches?.length} tranches) — edit it via import or the API.
        </p>
      ) : (
        <div className="space-y-2 rounded-lg border bg-muted/30 p-3">
          <p className="text-xs font-medium text-muted-foreground">Vesting schedule</p>
          <div className="grid grid-cols-3 gap-2">
            <Field label="Interval" htmlFor="eq-grant-interval">
              <Select id="eq-grant-interval" value={interval} onChange={(e) => setInterval(e.target.value)}>
                <option value="monthly">Monthly</option>
                <option value="quarterly">Quarterly</option>
                <option value="annual">Annual</option>
                <option value="none">Fully vested</option>
              </Select>
            </Field>
            {interval !== "none" && (
              <>
                <Field label="Installments" htmlFor="eq-grant-occurrences">
                  <Input id="eq-grant-occurrences" type="number" min="1" value={occurrences} onChange={(e) => setOccurrences(e.target.value)} className="tabular-nums" />
                </Field>
                <Field label="Cliff (installments)" htmlFor="eq-grant-cliff">
                  <Input id="eq-grant-cliff" type="number" min="0" value={cliff} onChange={(e) => setCliff(e.target.value)} className="tabular-nums" />
                </Field>
              </>
            )}
          </div>
          {interval !== "none" && (
            <p className="text-xs text-muted-foreground">
              e.g. the standard 4-year monthly schedule with a 1-year cliff is 48 installments, cliff 12.
            </p>
          )}
        </div>
      )}

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {isOption && (
          <>
            <Field label="Expiration date" htmlFor="eq-grant-expiration">
              <Input id="eq-grant-expiration" type="date" value={expiration} onChange={(e) => setExpiration(e.target.value)} />
            </Field>
            <Field label="Post-termination window (days)" htmlFor="eq-grant-pte">
              <Input id="eq-grant-pte" type="number" min="0" value={pteDays} onChange={(e) => setPteDays(e.target.value)} className="tabular-nums" />
            </Field>
          </>
        )}
        <Field label="Notes" htmlFor="eq-grant-notes" className={isOption ? "" : "col-span-2 sm:col-span-3"}>
          <Input id="eq-grant-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </div>

      <div className="flex flex-wrap gap-x-6 gap-y-2">
        {isOption && (
          <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
            <Checkbox checked={earlyExercisable} onChange={(e) => setEarlyExercisable(e.target.checked)} />
            Early exercisable
          </label>
        )}
        {grantType === "rsu" && (
          <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
            <Checkbox checked={doubleTrigger} onChange={(e) => setDoubleTrigger(e.target.checked)} />
            Double-trigger (settles at liquidity event)
          </label>
        )}
      </div>

    </FormDialog>
  );
}
