import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { queries } from "@/api/queries";
import { Button } from "@/components/ui/button";
import { Drawer, DrawerContent, DrawerHeader, DrawerFooter } from "@/components/ui/drawer";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Field } from "@/components/ui/field";
import { invalidate } from "@/api/keys";

const TRANSACTION_TYPES = ["Purchase", "Sale", "Dividend", "Foreign Dividend", "Interest", "Fees"] as const;
type TxType = typeof TRANSACTION_TYPES[number];

const QUANTITY_TYPES: TxType[] = ["Purchase", "Sale"];

interface Props {
  securityId: string;
  securityTicker: string;
  onClose: () => void;
  onCreated: () => void;
}

interface FormState {
  transaction_type: TxType;
  account_id: string;
  trade_date: string;
  quantity: string;
  price_usd: string;
  amount_usd: string;
  description: string;
}

const today = new Date().toISOString().slice(0, 10);

export function AddInvestmentTransactionDrawer({ securityId, securityTicker, onClose, onCreated }: Props) {
  const qc = useQueryClient();
  const { data: accounts = [] } = useQuery(queries.accounts());

  const [form, setForm] = useState<FormState>({
    transaction_type: "Purchase",
    account_id: "",
    trade_date: today,
    quantity: "",
    price_usd: "",
    amount_usd: "",
    description: "",
  });
  const [error, setError] = useState<string | null>(null);

  const set = (field: keyof FormState, value: string) =>
    setForm((f) => ({ ...f, [field]: value }));

  const needsQuantity = QUANTITY_TYPES.includes(form.transaction_type);

  const create = useMutation({
    mutationFn: () =>
      api.post("/investment_transactions", {
        security_id:      securityId,
        transaction_type: form.transaction_type,
        account_id:       form.account_id,
        trade_date:       form.trade_date,
        quantity:         form.quantity || undefined,
        price_usd:        form.price_usd || undefined,
        amount_usd:       form.amount_usd || undefined,
        description:      form.description || undefined,
      }),
    onSuccess: () => {
      invalidate(qc, queries.security(securityTicker).queryKey);
      onCreated();
    },
    onError: (e: Error) => setError(e.message ?? "Failed to save transaction"),
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!form.account_id) return setError("Account is required");
    if (!form.trade_date) return setError("Trade date is required");
    create.mutate();
  };

  return (
    <Drawer open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DrawerContent>
        <DrawerHeader title={`Add transaction · ${securityTicker}`} />

        <form onSubmit={handleSubmit} className="flex flex-1 flex-col overflow-y-auto">
          <div className="flex-1 space-y-4 p-4">

            <Field label="Type" htmlFor="add-tx-type">
              <Select
                id="add-tx-type"
                value={form.transaction_type}
                onChange={(e) => set("transaction_type", e.target.value)}
              >
                {TRANSACTION_TYPES.map((t) => <option key={t}>{t}</option>)}
              </Select>
            </Field>

            <Field label="Account" htmlFor="add-tx-account">
              <Select
                id="add-tx-account"
                value={form.account_id}
                onChange={(e) => set("account_id", e.target.value)}
                required
              >
                <option value="">Select account…</option>
                {accounts.map((a) => (
                  <option key={a.id} value={a.id}>{a.name}</option>
                ))}
              </Select>
            </Field>

            <Field label="Trade date" htmlFor="add-tx-date">
              <Input
                id="add-tx-date"
                type="date"
                value={form.trade_date}
                onChange={(e) => set("trade_date", e.target.value)}
                required
                className="tabular-nums"
              />
            </Field>

            {needsQuantity && (
              <div className="grid grid-cols-2 gap-3">
                <Field label="Quantity" htmlFor="add-tx-quantity">
                  <Input
                    id="add-tx-quantity"
                    type="number"
                    step="any"
                    placeholder="0.00"
                    value={form.quantity}
                    onChange={(e) => set("quantity", e.target.value)}
                    className="tabular-nums"
                  />
                </Field>
                <Field label="Price per share" htmlFor="add-tx-price">
                  <Input
                    id="add-tx-price"
                    type="number"
                    step="any"
                    placeholder="0.00"
                    value={form.price_usd}
                    onChange={(e) => set("price_usd", e.target.value)}
                    className="tabular-nums"
                  />
                </Field>
              </div>
            )}

            <Field label={needsQuantity ? "Total amount (USD)" : "Amount (USD)"} htmlFor="add-tx-amount">
              <Input
                id="add-tx-amount"
                type="number"
                step="any"
                placeholder="0.00"
                value={form.amount_usd}
                onChange={(e) => set("amount_usd", e.target.value)}
                className="tabular-nums"
              />
            </Field>

            <Field label="Description (optional)" htmlFor="add-tx-description">
              <Input
                id="add-tx-description"
                type="text"
                placeholder="e.g. Quarterly dividend"
                value={form.description}
                onChange={(e) => set("description", e.target.value)}
              />
            </Field>

            {error && <p className="text-xs text-destructive">{error}</p>}
          </div>

          <DrawerFooter>
            <Button type="submit" className="w-full" disabled={create.isPending}>
              {create.isPending ? "Saving…" : "Save transaction"}
            </Button>
          </DrawerFooter>
        </form>
      </DrawerContent>
    </Drawer>
  );
}
