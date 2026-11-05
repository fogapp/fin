import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { useMarketColumnPrefs } from "@/hooks/useMarketColumnPrefs";
import { workflowTriggerLine } from "@/pages/workflows/draftSteps";
import { Select } from "@/components/ui/select";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/PageState";
import { cn } from "@/lib/utils";
import type { WorkflowSummary } from "@/api/types";

/** The seeded scheduled workflows that own market-data syncing. */
const MARKET_SEED_KEYS = ["market_data_sync", "crypto_quotes_sync", "security_news_sync"] as const;

export function MarketSettings() {
  const { data: workflows = [], isLoading, isError, refetch } = useQuery(queries.workflows());
  const { prefs, setPrefs } = useMarketColumnPrefs();

  const syncWorkflows = MARKET_SEED_KEYS
    .map((key) => workflows.find((w) => w.seed_key === key))
    .filter((w): w is WorkflowSummary => !!w);

  return (
    <div className="space-y-8">
      <div className="space-y-4">
        <div>
          <p className="text-sm font-medium">Securities column</p>
          <p className="mt-0.5 text-xs text-muted-foreground">Choose what each row shows in the Market securities list.</p>
        </div>
        <div className="divide-y rounded-xl border">
          <ColumnPrefRow
            label="Primary"
            description="Main bold text"
            value={prefs.primary}
            options={[
              { value: "ticker", label: "Ticker" },
              { value: "name",   label: "Name" },
            ]}
            onChange={(v) => setPrefs({ primary: v as typeof prefs.primary })}
          />
          <ColumnPrefRow
            label="Subtitle"
            description="Small text below primary"
            value={prefs.subtitle}
            options={[
              { value: "name",   label: "Name" },
              { value: "ticker", label: "Ticker" },
              { value: "type",   label: "Type" },
              { value: "none",   label: "None" },
            ]}
            onChange={(v) => setPrefs({ subtitle: v as typeof prefs.subtitle })}
          />
          <ColumnPrefRow
            label="Right top"
            description="Primary value on the right"
            value={prefs.value1}
            options={[
              { value: "price",        label: "Price" },
              { value: "market_value", label: "Market value" },
              { value: "none",         label: "None" },
            ]}
            onChange={(v) => setPrefs({ value1: v as typeof prefs.value1 })}
          />
          <ColumnPrefRow
            label="Right bottom"
            description="Secondary value on the right"
            value={prefs.value2}
            options={[
              { value: "day_change", label: "Day change" },
              { value: "ytd_change", label: "YTD change" },
              { value: "none",       label: "None" },
            ]}
            onChange={(v) => setPrefs({ value2: v as typeof prefs.value2 })}
          />
          <ColumnPrefRow
            label="Sparkline"
            description="Inline 30-day trend line"
            value={prefs.sparkline ? "on" : "off"}
            options={[
              { value: "on",  label: "Show" },
              { value: "off", label: "Hide" },
            ]}
            onChange={(v) => setPrefs({ sparkline: v === "on" })}
          />
        </div>
      </div>

      <div className="space-y-4">
        <div>
          <p className="text-sm font-medium">Sync schedule</p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Market data syncs run as scheduled workflows — edit a schedule to change when it fetches.
          </p>
        </div>
        <div className="divide-y rounded-xl border">
          {isLoading && <SkeletonList rows={3} rowClassName="h-10 rounded-lg" className="p-4" />}
          {isError && <ErrorState title="Failed to load workflows" onRetry={() => refetch()} />}
          {syncWorkflows.map((w) => (
            <SyncWorkflowRow key={w.id} workflow={w} />
          ))}
          {!isLoading && !isError && syncWorkflows.length === 0 && (
            <EmptyState
              title="No market sync workflows found."
              description="They are seeded automatically for each household."
              className="py-6"
            />
          )}
        </div>
      </div>
    </div>
  );
}

function SyncWorkflowRow({ workflow: w }: { workflow: WorkflowSummary }) {
  return (
    <div className="flex items-center justify-between gap-4 px-4 py-3">
      <div className="min-w-0">
        <p className="flex items-center gap-2 text-sm font-medium">
          <span
            title={w.active ? "Active" : "Inactive"}
            className={cn("h-1.5 w-1.5 shrink-0 rounded-full", w.active ? "bg-positive" : "bg-muted-foreground/40")}
          />
          <span className="truncate">{w.name}</span>
        </p>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">{workflowTriggerLine(w)}</p>
      </div>
      <Link
        to={`/workflows/${w.id}`}
        className="shrink-0 rounded text-xs text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        Edit schedule
      </Link>
    </div>
  );
}

function ColumnPrefRow({ label, description, value, options, onChange }: {
  label: string;
  description: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex items-center justify-between px-4 py-3">
      <div>
        <p className="text-sm font-medium">{label}</p>
        <p className="text-xs text-muted-foreground">{description}</p>
      </div>
      <Select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-label={label}
        wrapperClassName="w-36 shrink-0"
        className="h-8 pl-2"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </Select>
    </div>
  );
}
