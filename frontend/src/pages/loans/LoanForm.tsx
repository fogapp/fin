import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldError } from "@/components/ui/field";
import type { Loan } from "@/api/types";
import { ESCROW_FIELDS, parseOptionalAmount } from "./escrow";
import { invalidate, keys } from "@/api/keys";

const LOAN_TYPES = ["mortgage", "auto", "student", "personal", "heloc", "business", "other"] as const;

interface LoanFormData {
  name: string;
  loan_type: string;
  status: string;
  account_id: string;
  merchant_id: string;
  original_principal: string;
  interest_rate: string;
  term_months: string;
  start_date: string;
  monthly_payment: string;
  escrow_property_tax: string;
  escrow_insurance: string;
  escrow_other: string;
  notes: string;
  interest_only: boolean;
}

type TextField = Exclude<keyof LoanFormData, "interest_only">;

const text = (value: string | number | null | undefined) => (value == null ? "" : String(value));

function initialData(loan: Loan | undefined, initialAccountId: string, initialName: string): LoanFormData {
  if (!loan) {
    return {
      name: initialName, loan_type: "auto", status: "active", account_id: initialAccountId, merchant_id: "",
      original_principal: "", interest_rate: "", term_months: "", start_date: "", monthly_payment: "",
      escrow_property_tax: "", escrow_insurance: "", escrow_other: "", notes: "", interest_only: false,
    };
  }

  return {
    name:                loan.name,
    loan_type:           loan.loan_type,
    status:              loan.status,
    account_id:          text(loan.account_id),
    merchant_id:         text(loan.merchant_id),
    original_principal:  text(loan.original_principal),
    interest_rate:       text(loan.interest_rate),
    term_months:         text(loan.term_months),
    start_date:          loan.start_date,
    // Only a payment the user entered — a computed one stays computed, so
    // editing the rate or term still moves it.
    monthly_payment:     text(loan.entered_monthly_payment),
    escrow_property_tax: text(loan.escrow_property_tax),
    escrow_insurance:    text(loan.escrow_insurance),
    escrow_other:        text(loan.escrow_other),
    notes:               text(loan.notes),
    interest_only:       loan.interest_only,
  };
}

/** Creates a loan, or edits `loan` when one is given. */
export function LoanForm({ loan, onSaved, onCancel, initialAccountId = "", initialName = "" }: {
  loan?: Loan;
  onSaved: (loan: Loan) => void;
  onCancel: () => void;
  initialAccountId?: string;
  initialName?: string;
}) {
  const qc = useQueryClient();
  const { data: accounts = [] } = useQuery(queries.accounts());
  const { data: merchants = [] } = useQuery(queries.merchants());
  const [error, setError] = useState("");
  const [form, setForm] = useState<LoanFormData>(() => initialData(loan, initialAccountId, initialName));

  const save = useMutation({
    mutationFn: () => {
      // Blank optional fields go up as null so an edit can clear them.
      const body = {
        name:                form.name,
        loan_type:           form.loan_type,
        status:              form.status,
        account_id:          form.account_id || null,
        merchant_id:         form.merchant_id || null,
        original_principal:  parseFloat(form.original_principal),
        interest_rate:       parseFloat(form.interest_rate),
        term_months:         parseInt(form.term_months),
        start_date:          form.start_date,
        monthly_payment:     parseOptionalAmount(form.monthly_payment),
        escrow_property_tax: parseOptionalAmount(form.escrow_property_tax),
        escrow_insurance:    parseOptionalAmount(form.escrow_insurance),
        escrow_other:        parseOptionalAmount(form.escrow_other),
        notes:               form.notes || null,
        interest_only:       form.interest_only,
      };
      return loan ? api.patch<Loan>(`/loans/${loan.id}`, body) : api.post<Loan>("/loans", body);
    },
    onSuccess: (saved) => {
      invalidate(qc, keys.loans);
      onSaved(saved);
    },
    onError: (err: Error) => setError(err.message),
  });

  function set(field: TextField, value: string) {
    setForm((f) => ({ ...f, [field]: value }));
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    save.mutate();
  }

  // Escrow only applies to mortgages, but never hide amounts already recorded.
  const showEscrow = form.loan_type === "mortgage" || ESCROW_FIELDS.some(({ key }) => form[key] !== "");

  return (
    <Card>
      <CardContent className="p-5">
        <h2 className="mb-4 text-sm font-semibold">{loan ? "Edit loan" : "New loan"}</h2>
        <form onSubmit={submit} className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Loan name" required htmlFor="loan-name">
              <Input
                id="loan-name"
                autoFocus
                required
                value={form.name}
                onChange={(e) => set("name", e.target.value)}
                placeholder="e.g. 30yr Mortgage"
              />
            </Field>
            <Field label="Lender (merchant)" htmlFor="loan-merchant">
              <Select id="loan-merchant" value={form.merchant_id} onChange={(e) => set("merchant_id", e.target.value)}>
                <option value="">None</option>
                {merchants.map((m) => (
                  <option key={m.id} value={m.id}>{m.name}</option>
                ))}
              </Select>
            </Field>
          </div>

          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="Type" required htmlFor="loan-type">
              <Select id="loan-type" required value={form.loan_type} onChange={(e) => set("loan_type", e.target.value)}>
                {LOAN_TYPES.map((t) => (
                  <option key={t} value={t}>{t.charAt(0).toUpperCase() + t.slice(1)}</option>
                ))}
              </Select>
            </Field>
            <Field label="Status" htmlFor="loan-status">
              <Select id="loan-status" value={form.status} onChange={(e) => set("status", e.target.value)}>
                <option value="active">Active</option>
                <option value="paid_off">Paid Off</option>
                <option value="refinanced">Refinanced</option>
              </Select>
            </Field>
            <Field label="Linked account" htmlFor="loan-account">
              <Select
                id="loan-account"
                value={form.account_id}
                onChange={(e) => set("account_id", e.target.value)}
                disabled={!!initialAccountId}
              >
                <option value="">None</option>
                {accounts.map((a) => (
                  <option key={a.id} value={a.id}>{a.name}</option>
                ))}
              </Select>
            </Field>
          </div>

          <div className="grid gap-3 sm:grid-cols-4">
            <Field label="Original principal" required htmlFor="loan-principal">
              <Input
                id="loan-principal"
                required
                type="number"
                step="0.01"
                min="0"
                value={form.original_principal}
                onChange={(e) => set("original_principal", e.target.value)}
                placeholder="400000"
                className="tabular-nums"
              />
            </Field>
            <Field label="Interest rate (APR %)" required htmlFor="loan-rate">
              <Input
                id="loan-rate"
                required
                type="number"
                step="0.001"
                min="0"
                value={form.interest_rate}
                onChange={(e) => set("interest_rate", e.target.value)}
                placeholder="6.500"
                className="tabular-nums"
              />
            </Field>
            <Field label="Term (months)" required htmlFor="loan-term">
              <Input
                id="loan-term"
                required
                type="number"
                step="1"
                min="1"
                value={form.term_months}
                onChange={(e) => set("term_months", e.target.value)}
                placeholder="360"
                className="tabular-nums"
              />
            </Field>
            <Field label="Monthly payment" htmlFor="loan-payment">
              <Input
                id="loan-payment"
                type="number"
                step="0.01"
                min="0"
                value={form.monthly_payment}
                onChange={(e) => set("monthly_payment", e.target.value)}
                placeholder="Auto-computed"
                className="tabular-nums"
              />
            </Field>
          </div>

          {showEscrow && (
            <div className="space-y-1.5">
              <div className="grid gap-3 sm:grid-cols-3">
                {ESCROW_FIELDS.map(({ key, label }) => (
                  <Field key={key} label={`${label} (monthly)`} htmlFor={`loan-${key}`}>
                    <Input
                      id={`loan-${key}`}
                      type="number"
                      step="0.01"
                      min="0"
                      value={form[key]}
                      onChange={(e) => set(key, e.target.value)}
                      placeholder="0.00"
                      className="tabular-nums"
                    />
                  </Field>
                ))}
              </div>
              <p className="text-xs text-muted-foreground">
                If your payment includes escrow, enter the full payment above and the escrowed amounts here.
                Only principal and interest count toward the payoff.
              </p>
            </div>
          )}

          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Start date" required htmlFor="loan-start">
              <Input
                id="loan-start"
                required
                type="date"
                value={form.start_date}
                onChange={(e) => set("start_date", e.target.value)}
              />
            </Field>
            <Field label="Notes" htmlFor="loan-notes">
              <Input
                id="loan-notes"
                value={form.notes}
                onChange={(e) => set("notes", e.target.value)}
                placeholder="Optional"
              />
            </Field>
          </div>

          <label className="flex items-center gap-2 text-sm cursor-pointer select-none">
            <Checkbox
              checked={form.interest_only}
              onChange={(e) => setForm((f) => ({ ...f, interest_only: e.target.checked }))}
            />
            Interest-only loan (payments cover interest only, principal stays constant)
          </label>

          <FieldError>{error}</FieldError>

          <div className="flex gap-2 pt-1">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={onCancel}
              className="text-muted-foreground hover:text-foreground"
            >
              Cancel
            </Button>
            <Button type="submit" size="sm" disabled={save.isPending}>
              {loan
                ? (save.isPending ? "Saving…" : "Save changes")
                : (save.isPending ? "Creating…" : "Create loan")}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
