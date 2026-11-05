import { useState, useEffect } from "react";
import { useMutation } from "@tanstack/react-query";
import { Pencil, Trash2, Plus, Check, X, Sparkles, AlertTriangle } from "lucide-react";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogFooter } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { formatCurrency, cn } from "@/lib/utils";
import { emptyForm, lotToForm, parseDecimal, type LotFormState } from "@/lib/lotForm";
import type { CostBasisLot, InvestmentLot, InvestmentLotPreview, Account } from "@/api/types";

function computedUnitCost(quantity: string, costBasis: string): number | null {
  const qty = parseDecimal(quantity);
  const cb  = parseDecimal(costBasis);
  return qty && cb && qty > 0 ? cb / qty : null;
}

// Compact control styling for in-table form rows.
const cellInput = "h-7 px-1.5 text-xs";

// ── Lot form fields (shared between edit and add rows) ────────────────────────

function LotFormFields({
  form,
  onChange,
  accounts,
}: {
  form: LotFormState;
  onChange: (f: LotFormState) => void;
  accounts: Account[];
}) {
  const unitCost = computedUnitCost(form.quantity, form.cost_basis);
  return (
    <>
      <td className="pl-10 pr-2 py-1.5">
        <Select
          autoFocus
          aria-label="Account"
          value={form.account_id}
          onChange={(e) => onChange({ ...form, account_id: e.target.value })}
          className={cn(cellInput, "pl-1.5 pr-6")}
        >
          <option value="">No account</option>
          {accounts.map((a) => (
            <option key={a.id} value={a.id}>{a.name}</option>
          ))}
        </Select>
      </td>
      <td className="px-2 py-1.5">
        <Input
          type="date"
          aria-label="Acquired date"
          value={form.acquired_date}
          onChange={(e) => onChange({ ...form, acquired_date: e.target.value })}
          className={cn(cellInput, "tabular-nums")}
        />
      </td>
      <td className="px-2 py-1.5">
        <Input
          type="number"
          step="any"
          aria-label="Quantity"
          value={form.quantity}
          onChange={(e) => onChange({ ...form, quantity: e.target.value })}
          placeholder="0"
          className={cn(cellInput, "text-right tabular-nums")}
        />
      </td>
      <td className="px-2 py-1.5">
        <Input
          type="number"
          step="any"
          aria-label="Cost basis"
          value={form.cost_basis}
          onChange={(e) => onChange({ ...form, cost_basis: e.target.value })}
          placeholder="0.00"
          className={cn(cellInput, "text-right tabular-nums")}
        />
      </td>
      <td className="px-3 py-1.5 text-right tabular-nums text-muted-foreground text-xs">
        {unitCost != null ? formatCurrency(unitCost) : "—"}
      </td>
      <td className="px-2 py-1.5">
        <Input
          aria-label="Notes"
          value={form.notes}
          onChange={(e) => onChange({ ...form, notes: e.target.value })}
          placeholder="Notes…"
          className={cellInput}
        />
      </td>
    </>
  );
}

/** Commit (✓) / cancel (✗) icon pair for an in-table form row.
 * Button order convention: cancel left, primary (commit) right. */
function RowCommitCancel({ onCommit, onCancel, saving }: {
  onCommit: () => void;
  onCancel: () => void;
  saving: boolean;
}) {
  return (
    <div className="flex items-center justify-end gap-1">
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label="Cancel"
        onClick={onCancel}
        className="text-muted-foreground"
      >
        <X size={13} />
      </Button>
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label="Save lot"
        onClick={onCommit}
        disabled={saving}
        className="text-positive hover:bg-positive/10 hover:text-positive"
      >
        <Check size={13} />
      </Button>
    </div>
  );
}

// ── Existing lot row ──────────────────────────────────────────────────────────

function LotRow({
  lot,
  accounts,
  onSave,
  onDelete,
}: {
  lot: CostBasisLot;
  accounts: Account[];
  onSave: (id: string, data: Record<string, unknown>) => Promise<void>;
  onDelete: (id: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<LotFormState>(lotToForm(lot));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function cancel() { setForm(lotToForm(lot)); setEditing(false); setError(null); }

  async function commit() {
    const qty = parseDecimal(form.quantity);
    const cb  = parseDecimal(form.cost_basis);
    if (!qty || !cb) {
      setError(!qty && !cb ? "Quantity and cost basis are required." : !qty ? "Quantity is required." : "Cost basis is required.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await onSave(lot.id, {
        account_id:    form.account_id || null,
        acquired_date: form.acquired_date || null,
        quantity:      qty,
        cost_basis:    cb,
        notes:         form.notes || null,
      });
      setEditing(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to save. Please try again.");
    } finally {
      setSaving(false);
    }
  }

  if (!editing) {
    return (
      <tr className="group text-xs border-b border-border/40 bg-muted/10 hover:bg-muted/20 transition-colors">
        <td className="pl-10 pr-2 py-2 text-muted-foreground">
          {lot.account_name ?? <span className="opacity-40">—</span>}
        </td>
        <td className="px-3 py-2 text-muted-foreground tabular-nums">
          {lot.acquired_date ?? <span className="opacity-40">—</span>}
        </td>
        <td className="px-3 py-2 text-right tabular-nums">{lot.quantity.toLocaleString()}</td>
        <td className="px-3 py-2 text-right tabular-nums">{formatCurrency(lot.cost_basis)}</td>
        <td className="px-3 py-2 text-right tabular-nums text-muted-foreground">
          {lot.unit_cost != null ? formatCurrency(lot.unit_cost) : "—"}
        </td>
        <td className="px-3 py-2 text-muted-foreground max-w-32 truncate">{lot.notes}</td>
        <td className="px-3 py-2">
          <div className="flex items-center justify-end gap-1">
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => setEditing(true)}
              className="text-muted-foreground hover:text-foreground"
              title="Edit lot"
              aria-label="Edit lot"
            >
              <Pencil size={12} />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => onDelete(lot.id)}
              className="text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
              title="Delete lot"
              aria-label="Delete lot"
            >
              <Trash2 size={12} />
            </Button>
          </div>
        </td>
      </tr>
    );
  }

  return (
    <>
      <tr className="text-xs border-b border-border/40 bg-primary/5">
        <LotFormFields form={form} onChange={(f) => { setForm(f); setError(null); }} accounts={accounts} />
        <td className="px-3 py-1.5">
          <RowCommitCancel onCommit={commit} onCancel={cancel} saving={saving} />
        </td>
      </tr>
      {error && (
        <tr className="bg-destructive/10">
          <td colSpan={7} className="pl-10 pr-3 py-1.5 text-xs text-destructive">{error}</td>
        </tr>
      )}
    </>
  );
}

// ── Add lot row ───────────────────────────────────────────────────────────────

function AddLotRow({
  securityId,
  accounts,
  onSaved,
  onCancel,
}: {
  securityId: string;
  accounts: Account[];
  onSaved: (lot: InvestmentLot) => void;
  onCancel: () => void;
}) {
  const [form, setForm] = useState<LotFormState>(emptyForm());
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const create = useMutation({
    mutationFn: (data: Record<string, unknown>) =>
      api.post<InvestmentLot>("/investment_lots", data),
  });

  async function commit() {
    const qty = parseDecimal(form.quantity);
    const cb  = parseDecimal(form.cost_basis);
    if (!qty || !cb) {
      setError(!qty && !cb ? "Quantity and cost basis are required." : !qty ? "Quantity is required." : "Cost basis is required.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const lot = await create.mutateAsync({
        security_id:   securityId,
        account_id:    form.account_id || null,
        acquired_date: form.acquired_date || null,
        quantity:      qty,
        cost_basis:    cb,
        notes:         form.notes || null,
      });
      onSaved(lot);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to save. Please try again.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <tr className="text-xs border-b border-border/40 bg-primary/5">
        <LotFormFields form={form} onChange={(f) => { setForm(f); setError(null); }} accounts={accounts} />
        <td className="px-3 py-1.5">
          <RowCommitCancel onCommit={commit} onCancel={onCancel} saving={saving} />
        </td>
      </tr>
      {error && (
        <tr className="bg-destructive/10">
          <td colSpan={7} className="pl-10 pr-3 py-1.5 text-xs text-destructive">{error}</td>
        </tr>
      )}
    </>
  );
}

// ── Generate preview modal ────────────────────────────────────────────────────

function GenerateModal({
  securityId,
  existingCount,
  onClose,
  onGenerated,
}: {
  securityId: string;
  existingCount: number;
  onClose: () => void;
  onGenerated: (lots: InvestmentLot[]) => void;
}) {
  const [preview, setPreview] = useState<InvestmentLotPreview[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [committing, setCommitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.post<InvestmentLotPreview[]>("/investment_lots/generate", { security_id: securityId })
      .then(setPreview)
      .catch(() => setError("Failed to load transaction history."))
      .finally(() => setLoading(false));
  }, [securityId]);

  async function handleCommit(replace: boolean) {
    setCommitting(true);
    try {
      const lots = await api.post<InvestmentLot[]>("/investment_lots/generate", {
        security_id: securityId,
        commit: true,
        replace,
      });
      onGenerated(lots);
    } catch {
      setError("Failed to generate lots. Please try again.");
      setCommitting(false);
    }
  }

  const totalBasis = preview?.reduce((s, l) => s + l.cost_basis, 0) ?? 0;

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent size="lg">
        <DialogHeader title="Generate lots from transactions" />

        {/* Body */}
        <div className="px-5 py-4 space-y-3">
          {existingCount > 0 && (
            <div className="flex items-start gap-2 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2.5 text-xs text-warning">
              <AlertTriangle size={13} className="mt-0.5 shrink-0" />
              <span>
                This security already has <strong>{existingCount}</strong> manually-defined {existingCount === 1 ? "lot" : "lots"}.
                Generating will replace {existingCount === 1 ? "it" : "them"}.
              </span>
            </div>
          )}

          {loading && (
            <div className="space-y-2 py-4">
              {[1, 2, 3].map((i) => (
                <Skeleton key={i} className="h-7" />
              ))}
            </div>
          )}

          {error && (
            <p className="py-4 text-center text-sm text-destructive">{error}</p>
          )}

          {preview && preview.length === 0 && (
            <p className="py-6 text-center text-sm text-muted-foreground">
              No purchase transactions found for this security.
            </p>
          )}

          {preview && preview.length > 0 && (
            <div className="max-h-72 overflow-y-auto rounded-lg border">
              <table className="w-full text-xs">
                <thead className="sticky top-0 bg-card">
                  <tr className="border-b text-caption text-muted-foreground">
                    <th className="px-3 py-2 text-left font-medium">Account</th>
                    <th className="px-3 py-2 text-left font-medium">Acquired</th>
                    <th className="px-3 py-2 text-right font-medium">Quantity</th>
                    <th className="px-3 py-2 text-right font-medium">Cost Basis</th>
                    <th className="px-3 py-2 text-right font-medium">Unit Cost</th>
                    <th className="px-3 py-2 text-left font-medium text-muted-foreground">Description</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {preview.map((lot, i) => (
                    <tr key={i} className="hover:bg-muted/40">
                      <td className="px-3 py-2 text-muted-foreground">{lot.account_name ?? "—"}</td>
                      <td className="px-3 py-2 tabular-nums text-muted-foreground">{lot.acquired_date ?? "—"}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{lot.quantity.toLocaleString()}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{formatCurrency(lot.cost_basis)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-muted-foreground">
                        {lot.unit_cost != null ? formatCurrency(lot.unit_cost) : "—"}
                      </td>
                      <td className="px-3 py-2 text-muted-foreground truncate max-w-40">{lot.description}</td>
                    </tr>
                  ))}
                </tbody>
                <tfoot>
                  <tr className="border-t font-medium text-caption">
                    <td className="px-3 py-2 text-muted-foreground" colSpan={2}>
                      Total ({preview.length} {preview.length === 1 ? "lot" : "lots"})
                    </td>
                    <td className="px-3 py-2 text-right tabular-nums">
                      {preview.reduce((s, l) => s + l.quantity, 0).toLocaleString()}
                    </td>
                    <td className="px-3 py-2 text-right tabular-nums">{formatCurrency(totalBasis)}</td>
                    <td colSpan={2} />
                  </tr>
                </tfoot>
              </table>
            </div>
          )}
        </div>

        <DialogFooter className="justify-between">
          <p className="text-xs text-muted-foreground">
            {preview && preview.length > 0 && "FIFO applied — sales consumed earliest lots first."}
          </p>
          <div className="flex items-center gap-2">
            <Button variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button
              onClick={() => handleCommit(existingCount > 0)}
              disabled={committing || loading || !preview || preview.length === 0}
              className="gap-1.5"
            >
              <Sparkles size={13} />
              {committing
                ? "Generating…"
                : existingCount > 0
                  ? `Replace with ${preview?.length ?? "…"} lots`
                  : `Generate ${preview?.length ?? "…"} lots`}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ── Main editor ───────────────────────────────────────────────────────────────

interface Props {
  securityId: string;
  lots: CostBasisLot[];
  accounts: Account[];
  onChanged: (lots: CostBasisLot[]) => void;
  className?: string;
}

export function InvestmentLotsEditor({ securityId, lots, accounts, onChanged, className }: Props) {
  const [adding, setAdding] = useState(false);
  const [generating, setGenerating] = useState(false);

  const updateLot = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Record<string, unknown> }) =>
      api.patch<InvestmentLot>(`/investment_lots/${id}`, data),
    onSuccess: (updated) => {
      onChanged(lots.map((l) => (l.id === updated.id ? updated : l)));
    },
  });

  const deleteLot = useMutation({
    mutationFn: (id: string) => api.delete(`/investment_lots/${id}`),
    onSuccess: (_res, id) => {
      onChanged(lots.filter((l) => l.id !== id));
    },
  });

  function handleAdded(lot: InvestmentLot) {
    setAdding(false);
    onChanged([...lots, lot]);
  }

  const totalQty   = lots.reduce((s, l) => s + l.quantity, 0);
  const totalBasis = lots.reduce((s, l) => s + l.cost_basis, 0);

  return (
    <div className={cn("overflow-x-auto", className)}>
      <table className="w-full text-xs min-w-[640px]">
        <thead>
          <tr className="border-b text-caption text-muted-foreground">
            <th className="pl-10 pr-2 py-2 text-left font-medium w-40">Account</th>
            <th className="px-3 py-2 text-left font-medium w-28">Acquired</th>
            <th className="px-3 py-2 text-right font-medium w-24">Quantity</th>
            <th className="px-3 py-2 text-right font-medium w-28">Cost Basis</th>
            <th className="px-3 py-2 text-right font-medium w-24">Unit Cost</th>
            <th className="px-3 py-2 text-left font-medium">Notes</th>
            <th className="px-3 py-2 w-16" />
          </tr>
        </thead>
        <tbody>
          {lots.length === 0 && !adding && (
            <tr>
              <td colSpan={7} className="pl-10 py-6 text-xs text-muted-foreground">
                No lots defined yet. Add a lot to track your cost basis.
              </td>
            </tr>
          )}
          {lots.map((lot) => (
            <LotRow
              key={lot.id}
              lot={lot}
              accounts={accounts}
              onSave={async (id, data) => { await updateLot.mutateAsync({ id, data }); }}
              onDelete={(id) => deleteLot.mutate(id)}
            />
          ))}
          {adding && (
            <AddLotRow
              securityId={securityId}
              accounts={accounts}
              onSaved={handleAdded}
              onCancel={() => setAdding(false)}
            />
          )}
        </tbody>
        {lots.length > 1 && (
          <tfoot>
            <tr className="border-t text-caption font-medium">
              <td className="pl-10 pr-2 py-1.5 text-muted-foreground" colSpan={2}>
                Total ({lots.length} lots)
              </td>
              <td className="px-3 py-1.5 text-right tabular-nums">{totalQty.toLocaleString()}</td>
              <td className="px-3 py-1.5 text-right tabular-nums">{formatCurrency(totalBasis)}</td>
              <td colSpan={3} />
            </tr>
          </tfoot>
        )}
      </table>
      {!adding && (
        <div className="flex items-center justify-between px-4 py-2.5 border-t">
          <Button
            variant="ghost"
            size="xs"
            onClick={() => setAdding(true)}
            className="gap-1.5 text-muted-foreground hover:text-foreground"
          >
            <Plus size={12} />
            Add lot
          </Button>
          <Button
            variant="ghost"
            size="xs"
            onClick={() => setGenerating(true)}
            className="gap-1.5 text-muted-foreground hover:text-foreground"
          >
            <Sparkles size={12} />
            Generate from transactions
          </Button>
        </div>
      )}

      {generating && (
        <GenerateModal
          securityId={securityId}
          existingCount={lots.length}
          onClose={() => setGenerating(false)}
          onGenerated={(generated) => { setGenerating(false); onChanged(generated); }}
        />
      )}
    </div>
  );
}
