import { useQuery } from "@tanstack/react-query";
import { Plus, Trash2 } from "lucide-react";
import { queries } from "@/api/queries";
import { DeferredInput } from "@/components/DeferredInput";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { humanize } from "./draftSteps";
import type { DraftCondition } from "./draftSteps";
import type { RegistryField } from "@/api/types";

// ── Condition rows ────────────────────────────────────────────────────────────
// Field/operator/value rows driven by the catalog fields of the workflow's
// subject — used by branch cards and the monitor trigger editor.

const NO_VALUE_OPS = new Set(["blank", "present"]);

export function ConditionRows({
  conditions, onChange, fields, matchAll,
}: {
  conditions: DraftCondition[];
  onChange: (cs: DraftCondition[]) => void;
  fields: Record<string, RegistryField>;
  matchAll: boolean;
}) {
  const fieldNames = Object.keys(fields);

  function patch(i: number, changes: Partial<DraftCondition>) {
    onChange(conditions.map((c, j) => (j === i ? { ...c, ...changes } : c)));
  }

  function add() {
    const field = fieldNames[0] ?? "";
    onChange([...conditions, { field, operator: fields[field]?.operators[0] ?? "", value: "" }]);
  }

  return (
    <div className="space-y-2">
      {conditions.length === 0 && (
        <p className="text-sm text-muted-foreground">No conditions — matches everything.</p>
      )}

      {conditions.map((c, i) => {
        const ops = fields[c.field]?.operators ?? [];
        const enumValues = fields[c.field]?.values;
        const noValue = NO_VALUE_OPS.has(c.operator);

        return (
          <div key={i}>
            {i > 0 && (
              <p className="py-1 text-center text-xs font-medium text-muted-foreground">
                {matchAll ? "AND" : "OR"}
              </p>
            )}
            <div className="flex items-center gap-2">
              <Select
                aria-label="Condition field"
                value={c.field}
                onChange={(e) => {
                  const field = e.target.value;
                  const newOps = fields[field]?.operators ?? [];
                  patch(i, { field, operator: newOps[0] ?? "", value: "" });
                }}
                wrapperClassName="w-48"
              >
                {fieldNames.map((f) => <option key={f} value={f}>{humanize(f)}</option>)}
              </Select>

              <Select
                aria-label="Condition operator"
                value={c.operator}
                onChange={(e) => {
                  const operator = e.target.value;
                  patch(i, NO_VALUE_OPS.has(operator) ? { operator, value: "" } : { operator });
                }}
                wrapperClassName="w-36"
              >
                {ops.map((o) => <option key={o} value={o}>{humanize(o)}</option>)}
              </Select>

              {!noValue && (
                enumValues ? (
                  <Select
                    aria-label="Condition value"
                    value={c.value}
                    onChange={(e) => patch(i, { value: e.target.value })}
                    wrapperClassName="flex-1"
                  >
                    <option value="">Select…</option>
                    {enumValues.map((v) => <option key={v} value={v}>{v}</option>)}
                  </Select>
                ) : (
                  <ConditionValueInput
                    field={c.field}
                    operator={c.operator}
                    value={c.value}
                    onChange={(value) => patch(i, { value })}
                  />
                )
              )}
              {noValue && <div className="flex-1" />}

              <button
                aria-label="Remove condition"
                onClick={() => onChange(conditions.filter((_, j) => j !== i))}
                className="shrink-0 rounded p-1 text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <Trash2 size={14} />
              </button>
            </div>
          </div>
        );
      })}

      <Button
        variant="ghost"
        size="xs"
        onClick={add}
        className="gap-1.5 text-muted-foreground hover:text-foreground"
      >
        <Plus size={13} />
        Add condition
      </Button>
    </div>
  );
}

// ── Value input ───────────────────────────────────────────────────────────────

function ConditionValueInput({
  field, operator, value, onChange,
}: {
  field: string; operator: string; value: string;
  onChange: (v: string) => void;
}) {
  const idFields = ["merchant_id", "category_id", "account_id"];
  const numericFields = ["amount", "balance", "balance_usd", "interest_rate", "average_amount", "confidence", "transaction_count", "quantity", "market_value", "unrealized_gain_loss", "transfer_counterpart_count"];

  if (idFields.includes(field)) {
    return <EntitySelect field={field} value={value} onChange={onChange} />;
  }

  return (
    <DeferredInput
      type={numericFields.includes(field) ? "number" : "text"}
      value={value}
      onCommit={onChange}
      placeholder={operator === "in" ? "value1, value2, …" : "value"}
    />
  );
}

function EntitySelect({ field, value, onChange }: { field: string; value: string; onChange: (v: string) => void }) {
  const { data: merchants = [] } = useQuery({ ...queries.merchants(), enabled: field === "merchant_id" });
  const { data: categories = [] } = useQuery({ ...queries.categories(), enabled: field === "category_id" });
  const { data: accounts = [] } = useQuery({ ...queries.accounts(), enabled: field === "account_id" });

  const options =
    field === "merchant_id" ? merchants.map((m) => ({ value: String(m.id), label: m.name })) :
    field === "category_id" ? categories.map((c) => ({ value: String(c.id), label: c.name })) :
    field === "account_id"  ? accounts.map((a) => ({ value: String(a.id), label: a.name })) : [];

  return (
    <Select
      aria-label="Condition value"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      wrapperClassName="flex-1"
    >
      <option value="">Select…</option>
      {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
    </Select>
  );
}
