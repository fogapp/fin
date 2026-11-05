import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { MerchantCombobox } from "@/components/MerchantCombobox";
import { CategoryCombobox } from "@/components/CategoryCombobox";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { cn } from "@/lib/utils";

// ── Action params ─────────────────────────────────────────────────────────────
// Per-action-type param editors matching the executor payload shapes.

const SYNC_TARGETS = ["plaid", "coinbase", "alchemy", "alchemy_transactions", "market_prices", "crypto_prices", "security_news", "system_audit", "reconciliation", "fx_rates", "recurring_detection"];

function ParamInput({ value, onChange, placeholder, type = "text" }: {
  value: string; onChange: (v: string) => void; placeholder: string; type?: string;
}) {
  return (
    <Input
      type={type}
      aria-label={placeholder}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      className="flex-1"
    />
  );
}

export function ActionParamsForm({
  actionType, params, onChange, workflowId,
}: {
  actionType: string;
  params: Record<string, unknown>;
  onChange: (p: Record<string, unknown>) => void;
  /** The workflow being edited — excluded from run_workflow targets. */
  workflowId?: string;
}) {
  const { data: merchants = [] } = useQuery({ ...queries.merchants(), enabled: actionType === "assign_merchant" });
  const { data: categories = [] } = useQuery({ ...queries.categories(), enabled: actionType === "assign_category" });
  const { data: accounts = [] } = useQuery({ ...queries.accounts(), enabled: actionType === "assign_account" || actionType === "transfer_to_account" });
  const { data: tags = [] } = useQuery({ ...queries.tags(), enabled: actionType === "add_tag" });
  const { data: loans = [] } = useQuery({ ...queries.loans(), enabled: actionType === "set_loan" });
  const { data: workflows = [] } = useQuery({ ...queries.workflows(), enabled: actionType === "run_workflow" });

  const str = (key: string) => String(params[key] ?? "");
  const set = (key: string) => (v: string) => onChange({ ...params, [key]: v });

  switch (actionType) {
    case "assign_merchant":
      return (
        <MerchantCombobox
          value={str("merchant_id")}
          onChange={(id) => onChange({ merchant_id: id || null })}
          merchants={merchants}
          className="flex-1"
        />
      );

    case "assign_category":
      return (
        <CategoryCombobox
          value={str("category_id")}
          onChange={(id) => onChange({ category_id: id || null })}
          categories={categories}
          className="flex-1"
        />
      );

    case "assign_account":
    case "transfer_to_account":
      return (
        <Select
          aria-label="Account"
          value={str("account_id")}
          onChange={(e) => onChange({ account_id: e.target.value || null })}
          wrapperClassName="flex-1"
        >
          <option value="">Select account…</option>
          {accounts.map((a) => (
            <option key={a.id} value={a.id}>
              {a.name}{a.kind === "external" ? " (external)" : ""}
            </option>
          ))}
        </Select>
      );

    case "add_tag": {
      const selectedIds: string[] = Array.isArray(params.tag_id) ? (params.tag_id as string[]).map(String) : [];
      return (
        <div className="flex flex-1 flex-wrap gap-1.5">
          {tags.map((tag) => {
            const selected = selectedIds.includes(String(tag.id));
            return (
              <button
                key={tag.id}
                type="button"
                aria-pressed={selected}
                onClick={() => {
                  const tagId = String(tag.id);
                  const next = selected ? selectedIds.filter((id) => id !== tagId) : [...selectedIds, tagId];
                  onChange({ tag_id: next });
                }}
                className={cn(
                  "rounded-full border px-2 py-0.5 text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                  selected ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground hover:bg-accent"
                )}
              >
                {tag.name}
              </button>
            );
          })}
          {tags.length === 0 && <span className="text-xs text-muted-foreground">No tags available</span>}
        </div>
      );
    }

    case "set_memo":
      return <ParamInput value={str("value")} onChange={set("value")} placeholder="Memo text" />;

    case "set_loan":
      return (
        <Select
          aria-label="Loan"
          value={str("loan_id")}
          onChange={(e) => onChange({ loan_id: e.target.value || null })}
          wrapperClassName="flex-1"
        >
          <option value="">Select loan…</option>
          {loans.map((l) => <option key={l.id} value={l.id}>{l.lender ? `${l.name} (${l.lender})` : l.name}</option>)}
        </Select>
      );

    case "mark_as_transfer":
      return <div className="flex-1" />;

    case "notify":
    case "create_issue": {
      const severities = actionType === "notify" ? ["info", "warning", "critical"] : ["info", "warning", "error"];
      return (
        <div className="flex-1 space-y-2">
          <div className="flex items-center gap-2">
            <ParamInput value={str("title")} onChange={set("title")} placeholder="Title" />
            <Select
              aria-label="Severity"
              value={str("severity") || "info"}
              onChange={(e) => set("severity")(e.target.value)}
              wrapperClassName="w-28"
            >
              {severities.map((s) => <option key={s} value={s}>{s}</option>)}
            </Select>
          </div>
          <ParamInput value={str("body")} onChange={set("body")} placeholder="Body" />
          <p className="text-xs text-muted-foreground">
            Title and body support {"{{field}}"} placeholders, filled from the subject's catalog fields.
          </p>
        </div>
      );
    }

    case "webhook":
      return (
        <div className="flex-1 space-y-1">
          <ParamInput value={str("url")} onChange={set("url")} placeholder="https://example.com/hook" type="url" />
          <p className="text-xs text-muted-foreground">HTTPS URLs only.</p>
        </div>
      );

    case "fog_event":
      return (
        <div className="flex-1 space-y-2">
          <div className="flex items-center gap-2">
            <ParamInput value={str("title")} onChange={set("title")} placeholder="Title (defaults to the workflow name)" />
            <Select
              aria-label="Severity"
              value={str("severity") || "info"}
              onChange={(e) => set("severity")(e.target.value)}
              wrapperClassName="w-28"
            >
              {["info", "warning", "critical"].map((s) => <option key={s} value={s}>{s}</option>)}
            </Select>
          </div>
          <ParamInput value={str("body")} onChange={set("body")} placeholder="Body" />
          <div className="flex items-center gap-2">
            <ParamInput value={str("type")} onChange={set("type")} placeholder="Type (defaults to the trigger)" />
            <ParamInput value={str("key")} onChange={set("key")} placeholder="Key (optional)" />
          </div>
          <ParamInput value={str("href")} onChange={set("href")} placeholder="Link, e.g. /review" />
          <p className="text-xs text-muted-foreground">
            {"Publishes fin.<type> to fog's household event stream for HUD to route; skipped when Fin isn't "
              + "running on fog. A later event with the same key replaces an earlier one. Fields support {{field}} placeholders."}
          </p>
        </div>
      );

    case "trigger_sync":
      return (
        <Select
          aria-label="Sync target"
          value={str("target")}
          onChange={(e) => set("target")(e.target.value)}
          wrapperClassName="flex-1"
        >
          <option value="">Select sync target…</option>
          {SYNC_TARGETS.map((t) => <option key={t} value={t}>{t.replace(/_/g, " ")}</option>)}
        </Select>
      );

    case "run_workflow":
      return (
        <Select
          aria-label="Workflow to run"
          value={str("workflow_id")}
          onChange={(e) => onChange({ workflow_id: e.target.value || null })}
          wrapperClassName="flex-1"
        >
          <option value="">Select workflow…</option>
          {workflows.filter((w) => w.id !== workflowId).map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
        </Select>
      );

    default:
      return <div className="flex-1" />;
  }
}
