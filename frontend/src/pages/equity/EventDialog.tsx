import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { FormDialog } from "@/components/ui/form-dialog";
import { Checkbox } from "@/components/ui/checkbox";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/toast";
import type { EquityGrant, EquityEventKind } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// Record a grant lifecycle event: exercise (options), settlement (RSU/RSA
// vest delivery), sale, or cancellation (departure/forfeiture). The share
// price captured here is what tax math needs later: FMV at exercise (AMT
// spread, basis), FMV at settlement (W-2 income), or the sale price.

export function EventDialog({ grant, companyName, onClose }: {
  grant: EquityGrant;
  companyName: string;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const isOption = grant.grant_type === "iso" || grant.grant_type === "nso";

  const [kind, setKind] = useState<EquityEventKind>(isOption ? "exercise" : "settlement");
  const [date, setDate] = useState("");
  const [quantity, setQuantity] = useState("");
  const [price, setPrice] = useState("");
  const [method, setMethod] = useState("cash");
  const [buyerType, setBuyerType] = useState("third_party");
  const [sharesWithheld, setSharesWithheld] = useState("");
  const [election83b, setElection83b] = useState(false);
  const [election83bDate, setElection83bDate] = useState("");
  const [notes, setNotes] = useState("");
  const [error, setError] = useState("");

  const priceLabel =
    kind === "sale" ? "Sale price per share"
    : kind === "cancellation" ? "Share price (optional)"
    : "FMV per share";

  const save = useMutation({
    mutationFn: () =>
      api.post(`/equity/grants/${grant.id}/events`, {
        kind,
        occurred_on: date,
        quantity: Number(quantity),
        share_price: price ? Number(price) : null,
        method: kind === "exercise" || kind === "settlement" ? method : null,
        buyer_type: kind === "sale" ? buyerType : null,
        election_83b: kind === "exercise" ? election83b : false,
        election_83b_date: kind === "exercise" && election83b ? election83bDate || null : null,
        shares_withheld: sharesWithheld ? Number(sharesWithheld) : null,
        notes: notes.trim() || null,
      }),
    onSuccess: () => {
      invalidate(qc, keys.equity);
      toast.success("Event recorded");
      onClose();
    },
    onError: (err: Error) => setError(err.message),
  });

  const canSave = !save.isPending && date !== "" && Number(quantity) > 0 &&
    (kind === "cancellation" || price !== "");

  return (
    <FormDialog
      title={`Record event — ${grant.label ?? companyName}`}
      size="md"
      onClose={onClose}
      onSubmit={() => save.mutate()}
      canSubmit={canSave}
      isPending={save.isPending}
      error={error}
      submitLabel="Record event"
    >
      <div className="grid grid-cols-2 gap-3">
        <Field label="Event" required htmlFor="eq-event-kind">
          <Select id="eq-event-kind" value={kind} onChange={(e) => setKind(e.target.value as EquityEventKind)}>
            {isOption && <option value="exercise">Exercise</option>}
            {!isOption && <option value="settlement">Vest settlement</option>}
            <option value="sale">Sale</option>
            <option value="cancellation">Cancellation / forfeiture</option>
          </Select>
        </Field>
        <Field label="Date" required htmlFor="eq-event-date">
          <Input id="eq-event-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </Field>
        <Field label="Shares" required htmlFor="eq-event-qty">
          <Input id="eq-event-qty" type="number" step="any" min="0" value={quantity} onChange={(e) => setQuantity(e.target.value)} className="tabular-nums" />
        </Field>
        <Field label={priceLabel} required={kind !== "cancellation"} htmlFor="eq-event-price">
          <Input id="eq-event-price" type="number" step="any" min="0" value={price} onChange={(e) => setPrice(e.target.value)} className="tabular-nums" />
        </Field>

        {(kind === "exercise" || kind === "settlement") && (
          <Field label="Method" htmlFor="eq-event-method">
            <Select id="eq-event-method" value={method} onChange={(e) => setMethod(e.target.value)}>
              <option value="cash">Cash</option>
              <option value="cashless">Cashless</option>
              <option value="sell_to_cover">Sell to cover</option>
              <option value="net_settlement">Net settlement</option>
            </Select>
          </Field>
        )}
        {kind === "sale" && (
          <Field label="Buyer" htmlFor="eq-event-buyer">
            <Select id="eq-event-buyer" value={buyerType} onChange={(e) => setBuyerType(e.target.value)}>
              <option value="third_party">Third party / market</option>
              <option value="company_tender">Company tender offer</option>
            </Select>
          </Field>
        )}
        {(method === "sell_to_cover" || method === "net_settlement") && kind !== "sale" && kind !== "cancellation" && (
          <Field label="Shares withheld / sold to cover" htmlFor="eq-event-withheld">
            <Input id="eq-event-withheld" type="number" step="any" min="0" value={sharesWithheld} onChange={(e) => setSharesWithheld(e.target.value)} className="tabular-nums" />
          </Field>
        )}
      </div>

      {kind === "exercise" && grant.early_exercisable && (
        <div className="flex items-center gap-4">
          <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
            <Checkbox checked={election83b} onChange={(e) => setElection83b(e.target.checked)} />
            83(b) election filed
          </label>
          {election83b && (
            <Input
              type="date"
              aria-label="83(b) filing date"
              value={election83bDate}
              onChange={(e) => setElection83bDate(e.target.value)}
              className="w-40"
            />
          )}
        </div>
      )}

      <Field label="Notes" htmlFor="eq-event-notes">
        <Input id="eq-event-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
      </Field>
    </FormDialog>
  );
}
