import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link2, ChevronLeft } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogFooter } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Field } from "@/components/ui/field";
import type { Account } from "@/api/types";
import { invalidate, keys } from "@/api/keys";
import { usePlaidLinkFlow } from "@/hooks/usePlaidLinkFlow";

const ACCOUNT_TYPES = [
  "Checking",
  "Savings",
  "Credit Card",
  "Brokerage",
  "Retirement",
  "Invt Mgmt",
  "Mortgage",
  "Loan",
  "Other",
];

interface Props {
  onClose: () => void;
  onCreated?: (account: Account) => void;
}

export function NewAccountForm({ onClose, onCreated }: Props) {
  const [step, setStep] = useState<"choose" | "manual">("choose");

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent size="md">
        <DialogHeader title={step === "choose" ? "Add account" : "New account"} />
        {step === "choose" ? (
          <ChooseStep
            onClose={onClose}
            onManual={() => setStep("manual")}
          />
        ) : (
          <ManualForm onClose={onClose} onCreated={onCreated} onBack={() => setStep("choose")} />
        )}
      </DialogContent>
    </Dialog>
  );
}

// ── Choose: Plaid prompt with manual fallback ─────────────────────────────────

function ChooseStep({ onClose, onManual }: { onClose: () => void; onManual: () => void }) {
  const { open, canOpen, tokenLoading, tokenError, linking, error } = usePlaidLinkFlow({ onLinked: onClose });

  return (
    <div className="space-y-5 px-5 py-4">
      <div className="space-y-2">
        <p className="text-sm font-medium">Connect your bank with Plaid</p>
        <p className="text-sm text-muted-foreground">
          Securely link a bank, credit card, or brokerage account to sync balances and
          transactions automatically.
        </p>
      </div>

      <Button
        type="button"
        onClick={open}
        disabled={!canOpen}
        className="w-full gap-2"
      >
        <Link2 size={15} />
        {linking
          ? "Linking account…"
          : tokenLoading
            ? "Preparing Plaid…"
            : "Connect with Plaid"}
      </Button>

      {tokenError && (
        <p className="text-sm text-destructive">
          Couldn't reach Plaid. Try again or add the account manually.
        </p>
      )}
      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="border-t pt-4 text-center">
        <button
          type="button"
          onClick={onManual}
          className="rounded text-sm text-muted-foreground underline-offset-2 hover:text-foreground hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          Add an account manually instead
        </button>
      </div>
    </div>
  );
}

// ── Manual creation form ──────────────────────────────────────────────────────

function ManualForm({ onClose, onCreated, onBack }: {
  onClose: () => void;
  onCreated?: (a: Account) => void;
  onBack: () => void;
}) {
  const qc = useQueryClient();
  const { data: brokers = [] } = useQuery(queries.brokers());

  const [name, setName] = useState("");
  const [accountNumber, setAccountNumber] = useState("");
  const [accountType, setAccountType] = useState("");
  const [brokerId, setBrokerId] = useState("");
  const [creatingBroker, setCreatingBroker] = useState(false);
  const [newBrokerName, setNewBrokerName] = useState("");
  const [error, setError] = useState("");

  const createBroker = useMutation({
    mutationFn: (brokerName: string) =>
      api.post<{ id: string; name: string }>("/brokers", { name: brokerName.trim() }),
    onSuccess: (broker) => {
      invalidate(qc, keys.brokers);
      setBrokerId(broker.id);
      setNewBrokerName("");
      setCreatingBroker(false);
    },
    onError: (err: Error) => setError(err.message),
  });

  const create = useMutation({
    mutationFn: () =>
      api.post<Account>("/accounts", {
        name: name.trim(),
        account_number: accountNumber.trim(),
        account_type: accountType || null,
        broker_id: brokerId || null,
      }),
    onSuccess: (account) => {
      invalidate(qc, keys.accounts);
      onCreated?.(account);
      onClose();
    },
    onError: (err: Error) => setError(err.message),
  });

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    if (!name.trim()) { setError("Name is required."); return; }
    if (!brokerId)    { setError("Broker is required."); return; }
    create.mutate();
  }

  return (
    <form onSubmit={handleSubmit}>
      <div className="space-y-4 px-5 py-4">
        <Field label="Name" required htmlFor="new-account-name">
          <Input
            id="new-account-name"
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Fidelity Brokerage"
          />
        </Field>

        <Field label="Broker" required htmlFor="new-account-broker">
          {creatingBroker ? (
            <div className="flex items-center gap-2">
              <Input
                autoFocus
                aria-label="Broker name"
                value={newBrokerName}
                onChange={(e) => setNewBrokerName(e.target.value)}
                placeholder="Broker name"
                onKeyDown={(e) => {
                  if (e.key === "Enter" && newBrokerName.trim()) {
                    e.preventDefault();
                    setError("");
                    createBroker.mutate(newBrokerName);
                  } else if (e.key === "Escape") {
                    e.stopPropagation();
                    setCreatingBroker(false);
                    setNewBrokerName("");
                  }
                }}
              />
              <Button
                type="button"
                size="sm"
                disabled={!newBrokerName.trim() || createBroker.isPending}
                onClick={() => { setError(""); createBroker.mutate(newBrokerName); }}
              >
                {createBroker.isPending ? "Adding…" : "Add"}
              </Button>
              <Button
                type="button"
                size="sm"
                variant="ghost"
                onClick={() => { setCreatingBroker(false); setNewBrokerName(""); }}
              >
                Cancel
              </Button>
            </div>
          ) : (
            <div className="flex items-center gap-2">
              <Select
                id="new-account-broker"
                value={brokerId}
                onChange={(e) => setBrokerId(e.target.value)}
                wrapperClassName="flex-1"
              >
                <option value="">Select broker…</option>
                {brokers.map((b) => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </Select>
              <Button type="button" size="sm" variant="outline" onClick={() => setCreatingBroker(true)}>
                + New
              </Button>
            </div>
          )}
        </Field>

        <Field label="Account type" htmlFor="new-account-type">
          <Select
            id="new-account-type"
            value={accountType}
            onChange={(e) => setAccountType(e.target.value)}
          >
            <option value="">Select type…</option>
            {ACCOUNT_TYPES.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </Select>
        </Field>

        <Field label="Account number" htmlFor="new-account-number">
          <Input
            id="new-account-number"
            value={accountNumber}
            onChange={(e) => setAccountNumber(e.target.value)}
            placeholder="Last 4 digits or full number"
          />
        </Field>

        {error && <p className="text-sm text-destructive">{error}</p>}
      </div>

      <DialogFooter>
        <Button type="button" variant="ghost" onClick={onBack} className="mr-auto gap-1 text-muted-foreground hover:text-foreground">
          <ChevronLeft size={14} />
          Back
        </Button>
        <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
        <Button type="submit" disabled={create.isPending}>
          {create.isPending ? "Creating…" : "Create account"}
        </Button>
      </DialogFooter>
    </form>
  );
}
