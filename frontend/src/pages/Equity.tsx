import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Briefcase, CalendarClock, Plus, Pencil, Trash2, TriangleAlert } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { usePreferences } from "@/hooks/usePreferences";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon } from "@/components/StatRibbon";
import { ErrorState } from "@/components/PageState";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/toast";
import { Checkbox } from "@/components/ui/checkbox";
import { formatCurrency, formatDate } from "@/lib/utils";
import { CompanyDialog } from "./equity/CompanyDialog";
import { GrantDialog } from "./equity/GrantDialog";
import { EventDialog } from "./equity/EventDialog";
import { FmvDialog } from "./equity/FmvDialog";
import { GrantRow } from "./equity/GrantRow";
import { ExercisePlannerDialog } from "./equity/ExercisePlannerDialog";
import type { EquityCompany, EquityGrant } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Equity ────────────────────────────────────────────────────────────────────
// Equity compensation: companies (public by ticker, private by FMV history),
// grants with vesting schedules, and lifecycle events. Two-lane valuation:
// vested value (haircut by an assumed tax rate) is real; unvested/private
// value is "paper". Net worth counts the vested lane only, unless the
// household flips the toggle at the bottom of this page.

const DEFAULT_HAIRCUT_PCT = 30;

export function Equity() {
  const { data, isLoading, isError, refetch } = useQuery(queries.equitySummary());
  const { prefs, set: setPref } = usePreferences();

  const haircutPct = typeof prefs["equity.tax_haircut_pct"] === "number"
    ? (prefs["equity.tax_haircut_pct"] as number)
    : DEFAULT_HAIRCUT_PCT;

  const [companyDialog, setCompanyDialog] = useState<{ company?: EquityCompany } | null>(null);
  const [grantDialog, setGrantDialog] = useState<{ company: EquityCompany; grant?: EquityGrant } | null>(null);
  const [eventDialog, setEventDialog] = useState<{ grant: EquityGrant; companyName: string } | null>(null);
  const [fmvDialog, setFmvDialog] = useState<EquityCompany | null>(null);
  const [plannerDialog, setPlannerDialog] = useState<{ grant: EquityGrant; companyName: string } | null>(null);
  // Per-company scenario ("what if") share prices, keyed by company id.
  const [whatIf, setWhatIf] = useState<Record<string, string>>({});

  if (isLoading) {
    return (
      <div className="flex flex-col">
        <PageHeader title="Equity" level={1} sticky />
        <div className="space-y-6 p-6">
          <Skeleton className="h-24 rounded-xl" />
          <Skeleton className="h-64 rounded-xl" />
        </div>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="flex flex-col">
        <PageHeader title="Equity" level={1} sticky />
        <ErrorState title="Failed to load equity data" onRetry={() => refetch()} />
      </div>
    );
  }

  const { companies, totals } = data;
  const afterTax = totals.vested_value * (1 - haircutPct / 100);
  const nextVest = totals.upcoming_vests[0];

  return (
    <div className="flex flex-col">
      <PageHeader
        title="Equity"
        level={1}
        sticky
        actions={[ { label: "Add company", icon: Plus, onSelect: () => setCompanyDialog({}) } ]}
      />

      <StatRibbon borderTop={false} stats={[
        { label: "Vested value", value: formatCurrency(totals.vested_value) },
        { label: `After tax (~${haircutPct}%)`, value: formatCurrency(afterTax) },
        { label: "Unvested (paper)", value: formatCurrency(totals.unvested_value), dividerBefore: true },
        { label: "Next vest", value: nextVest ? `${formatDate(nextVest.date)}${nextVest.value != null ? ` · ${formatCurrency(nextVest.value, true)}` : ""}` : "—" },
      ]} />

      <div className="space-y-6 p-6">
        {companies.length === 0 ? (
          <div className="rounded-xl border">
            <EmptyState
              icon={Briefcase}
              title="No equity yet."
              description="Add the company you have equity in, then record your grants — options, RSUs, or restricted stock. Private companies are valued by their 409A history; public ones track the market."
              action={
                <Button size="sm" onClick={() => setCompanyDialog({})} className="gap-1">
                  <Plus size={13} />
                  Add company
                </Button>
              }
            />
          </div>
        ) : (
          <>
            {/* Upcoming vests */}
            {totals.upcoming_vests.length > 0 && (
              <section className="overflow-hidden rounded-xl border">
                <div className="flex items-center gap-2 border-b bg-muted/30 px-4 py-2.5">
                  <CalendarClock size={14} className="text-muted-foreground" />
                  <h2 className="text-sm font-semibold">Upcoming vests</h2>
                  <span className="text-xs text-muted-foreground">next 12 months</span>
                </div>
                <div className="divide-y">
                  {totals.upcoming_vests.slice(0, 6).map((v, i) => (
                    <div key={i} className="flex items-center gap-3 px-4 py-2 text-sm">
                      <span className="w-24 shrink-0 text-xs text-muted-foreground">{formatDate(v.date)}</span>
                      <span className="min-w-0 flex-1 truncate">
                        {v.company_name}
                        <span className="text-muted-foreground"> · {v.grant_label ?? v.grant_type.toUpperCase()}</span>
                      </span>
                      <span className="tabular-nums text-muted-foreground">{v.quantity.toLocaleString()} sh</span>
                      <span className="w-24 text-right tabular-nums font-medium">
                        {v.value != null ? formatCurrency(v.value) : "—"}
                      </span>
                    </div>
                  ))}
                  {totals.upcoming_vests.length > 6 && (
                    <p className="px-4 py-1.5 text-xs text-muted-foreground">
                      +{totals.upcoming_vests.length - 6} more in the next year
                    </p>
                  )}
                </div>
              </section>
            )}

            {/* Companies */}
            {companies.map((c) => (
              <CompanyCard
                key={c.id}
                company={c}
                whatIf={whatIf[c.id] ?? ""}
                onWhatIfChange={(v) => setWhatIf((prev) => ({ ...prev, [c.id]: v }))}
                onEdit={() => setCompanyDialog({ company: c })}
                onAddGrant={() => setGrantDialog({ company: c })}
                onRecordFmv={() => setFmvDialog(c)}
                onEditGrant={(grant) => setGrantDialog({ company: c, grant })}
                onRecordEvent={(grant) => setEventDialog({ grant, companyName: c.name })}
                onPlanExercise={(grant) => setPlannerDialog({ grant, companyName: c.name })}
              />
            ))}

            {/* Net worth scope */}
            <NetWorthScopeToggle />

            {/* Tax haircut assumption */}
            <p className="flex items-center gap-2 text-xs text-muted-foreground">
              After-tax value assumes a
              <Input
                type="number"
                min="0"
                max="60"
                aria-label="Tax haircut percent"
                value={haircutPct}
                onChange={(e) => setPref("equity.tax_haircut_pct", Number(e.target.value))}
                className="h-6 w-14 px-1.5 text-xs tabular-nums"
              />
              % haircut on vested value — an estimate, not tax advice.
            </p>
          </>
        )}
      </div>

      {companyDialog && <CompanyDialog company={companyDialog.company} onClose={() => setCompanyDialog(null)} />}
      {grantDialog && <GrantDialog company={grantDialog.company} grant={grantDialog.grant} onClose={() => setGrantDialog(null)} />}
      {eventDialog && <EventDialog grant={eventDialog.grant} companyName={eventDialog.companyName} onClose={() => setEventDialog(null)} />}
      {fmvDialog && <FmvDialog company={fmvDialog} onClose={() => setFmvDialog(null)} />}
      {plannerDialog && (
        <ExercisePlannerDialog
          grant={plannerDialog.grant}
          companyName={plannerDialog.companyName}
          onClose={() => setPlannerDialog(null)}
        />
      )}
    </div>
  );
}

// ── Net worth scope ───────────────────────────────────────────────────────────
// Vested equity always counts toward net worth (options at their intrinsic
// spread). Unvested shares are opt-in and household-wide, so the switch is
// admin-only — it changes the number everyone in the household sees.

function NetWorthScopeToggle() {
  const qc = useQueryClient();
  const { data: me } = useQuery(queries.me());
  const isAdmin = me?.household.role === "admin";
  const includeUnvested = me?.household.include_unvested_equity ?? false;

  const update = useMutation({
    mutationFn: (include_unvested_equity: boolean) =>
      api.patch(`/households/${me?.household.id}`, { include_unvested_equity }),
    onSuccess: () => {
      invalidate(qc, keys.me, keys.households, keys.netWorth);
    },
    onError: () => toast.error("Couldn't update the net worth setting."),
  });

  return (
    <label className="flex items-center gap-2 text-xs text-muted-foreground">
      <Checkbox
        checked={includeUnvested}
        disabled={!isAdmin || update.isPending}
        onChange={(e) => update.mutate(e.target.checked)}
      />
      Count unvested shares toward net worth. Vested value always counts
      {isAdmin ? "." : " — admins only."}
    </label>
  );
}

// ── Company card ──────────────────────────────────────────────────────────────

function CompanyCard({ company: c, whatIf, onWhatIfChange, onEdit, onAddGrant, onRecordFmv, onEditGrant, onRecordEvent, onPlanExercise }: {
  company: EquityCompany;
  whatIf: string;
  onWhatIfChange: (v: string) => void;
  onEdit: () => void;
  onAddGrant: () => void;
  onRecordFmv: () => void;
  onEditGrant: (grant: EquityGrant) => void;
  onRecordEvent: (grant: EquityGrant) => void;
  onPlanExercise: (grant: EquityGrant) => void;
}) {
  const qc = useQueryClient();
  const confirm = useConfirm();

  const destroy = useMutation({
    mutationFn: () => api.delete(`/equity/companies/${c.id}`),
    onSuccess: () => {
      invalidate(qc, keys.equity);
      toast.success("Company deleted");
    },
  });

  async function handleDelete() {
    const ok = await confirm({
      title: `Delete ${c.name}?`,
      description: `${c.grants.length} grants and their events will be removed.`,
      confirmLabel: "Delete",
      destructive: true,
    });
    if (ok) destroy.mutate();
  }

  const whatIfPrice = whatIf !== "" && Number(whatIf) >= 0 ? Number(whatIf) : null;

  return (
    <section className="overflow-hidden rounded-xl border">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b bg-muted/30 px-4 py-2.5">
        <h2 className="text-sm font-semibold">{c.name}</h2>
        <Badge variant={c.public_company ? "default" : "outline"}>
          {c.public_company ? (c.ticker ?? "Public") : "Private"}
        </Badge>
        {c.qsbs_candidate && <Badge variant="outline">QSBS</Badge>}

        {c.share_price != null ? (
          <span className="text-xs text-muted-foreground">
            {formatCurrency(c.share_price)}/sh
            {!c.public_company && c.latest_fmv && (
              <> · {c.latest_fmv.source} {formatDate(c.latest_fmv.effective_date)}</>
            )}
          </span>
        ) : (
          <span className="text-xs text-muted-foreground">No share value yet</span>
        )}
        {c.latest_fmv?.stale && !c.public_company && (
          <span className="flex items-center gap-1 text-xs text-warning">
            <TriangleAlert size={12} />
            FMV over a year old
          </span>
        )}

        <div className="ml-auto flex items-center gap-1.5">
          <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
            What if
            <Input
              type="number"
              step="any"
              min="0"
              aria-label={`Scenario price for ${c.name}`}
              value={whatIf}
              onChange={(e) => onWhatIfChange(e.target.value)}
              placeholder={c.share_price != null ? String(c.share_price) : "$/sh"}
              className="h-7 w-20 px-2 text-xs tabular-nums"
            />
          </label>
          {!c.public_company && (
            <Button variant="ghost" size="xs" onClick={onRecordFmv}>Record FMV</Button>
          )}
          <Button variant="ghost" size="xs" onClick={onAddGrant} className="gap-1">
            <Plus size={12} />
            Grant
          </Button>
          <Button variant="ghost" size="icon-sm" aria-label={`Edit ${c.name}`} onClick={onEdit}>
            <Pencil size={13} />
          </Button>
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={`Delete ${c.name}`}
            onClick={handleDelete}
            className="text-destructive hover:bg-destructive/10 hover:text-destructive"
          >
            <Trash2 size={13} />
          </Button>
        </div>
      </div>

      {c.grants.length === 0 ? (
        <EmptyState
          title="No grants yet."
          description="Add a grant to start tracking its vesting."
          action={<Button variant="outline" size="sm" onClick={onAddGrant}>Add grant</Button>}
          className="py-8"
        />
      ) : (
        <>
          <div className="grid grid-cols-[auto_minmax(0,1.5fr)_1fr_1fr_1fr_1.2fr] gap-3 border-b px-4 py-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            <span className="w-3.5" />
            <span>Grant</span>
            <span>Shares</span>
            <span>Vested</span>
            <span>Strike</span>
            <span className="text-right">Value{whatIfPrice != null && ` @ ${formatCurrency(whatIfPrice)}`}</span>
          </div>
          <div className="divide-y">
            {c.grants.map((g) => (
              <GrantRow
                key={g.id}
                grant={g}
                company={c}
                whatIfPrice={whatIfPrice}
                onEdit={() => onEditGrant(g)}
                onRecordEvent={() => onRecordEvent(g)}
                onPlanExercise={() => onPlanExercise(g)}
              />
            ))}
          </div>
        </>
      )}
    </section>
  );
}
