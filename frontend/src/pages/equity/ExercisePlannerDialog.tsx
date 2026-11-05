import { useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { CalendarClock, Pencil, TriangleAlert } from "lucide-react";
import { api } from "@/api/client";
import { queries } from "@/api/queries";
import { Dialog, DialogContent, DialogHeader } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { SkeletonList } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { useDebounced } from "@/hooks/useDebounced";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import { TaxProfileForm } from "./TaxProfileForm";
import type { EquityGrant, ExercisePlan, ExercisePlanScenario } from "@/api/types";
import { keys } from "@/api/keys";

// ── Exercise planner ──────────────────────────────────────────────────────────
// "How many options can I exercise this year, what will it cost, and when is
// the tax due?" — federal Form 6251 + California Schedule P engines run
// server-side; this dialog is the scenario explorer. Everything shown is an
// estimate under the stated assumptions, never advice.

export function ExercisePlannerDialog({ grant, companyName, onClose }: {
  grant: EquityGrant;
  companyName: string;
  onClose: () => void;
}) {
  const taxYear = new Date().getFullYear();
  const [editingProfile, setEditingProfile] = useState(false);
  const [quantity, setQuantity] = useState<number | null>(null); // null → crossover default
  const [dropPct, setDropPct] = useState(60);

  const { data: profile } = useQuery(queries.taxProfile(taxYear));
  const profileComplete = profile?.complete ?? false;

  const debouncedQty = useDebounced(quantity, 350);
  const { data: plan, isPending, isError, refetch } = useQuery({
    queryKey: [...keys.equity, "exercise_plan", grant.id, taxYear, debouncedQty, dropPct],
    queryFn: () =>
      api.post<ExercisePlan>(`/equity/grants/${grant.id}/exercise_plan`, {
        tax_year: taxYear,
        ...(debouncedQty != null ? { quantity: debouncedQty } : {}),
        stress_drop_pct: dropPct,
      }),
    enabled: profileComplete && !editingProfile,
    placeholderData: keepPreviousData,
  });

  const isIso = grant.grant_type === "iso";
  const qty = plan?.simulation.quantity ?? 0;

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent size="lg">
        <DialogHeader title={`Exercise planner — ${grant.label ?? companyName}`} />

        <div className="max-h-[70vh] space-y-4 overflow-y-auto p-5">
          {/* Tax profile strip / editor */}
          {profile && (editingProfile || !profileComplete) ? (
            <div className="rounded-lg border bg-muted/30 p-4">
              {!profileComplete && (
                <p className="mb-3 text-sm text-muted-foreground">
                  The planner needs a {taxYear} tax profile — income and filing details drive the AMT math.
                </p>
              )}
              <TaxProfileForm
                profile={profile}
                onSaved={() => setEditingProfile(false)}
                onCancel={profileComplete ? () => setEditingProfile(false) : undefined}
              />
            </div>
          ) : profile && (
            <button
              onClick={() => setEditingProfile(true)}
              className="flex w-full items-center gap-2 rounded-lg border bg-muted/30 px-3 py-2 text-left text-xs text-muted-foreground transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <span className="font-medium text-foreground">{taxYear} tax profile</span>
              {profile.filing_status === "mfj" ? "Married filing jointly" : "Single"} · {profile.state} ·
              wages {formatCurrency(profile.projected_wages, true)}
              {profile.itemizing && " · itemizing"}
              <Pencil size={12} className="ml-auto shrink-0" />
            </button>
          )}

          {profileComplete && !editingProfile && (
            <>
              {isPending && !plan ? (
                <SkeletonList rows={4} rowClassName="h-16 rounded-xl" />
              ) : isError ? (
                <ErrorState title="Couldn't compute the plan" onRetry={() => refetch()} />
              ) : plan && (
                <>
                  {/* Hero — the crossover */}
                  {isIso && plan.crossover && (
                    <div className="rounded-xl border bg-primary/5 px-4 py-3">
                      <p className="text-sm">
                        You can exercise{" "}
                        <span className="text-lg font-semibold tabular-nums">{plan.crossover.shares.toLocaleString()}</span>{" "}
                        shares ({formatCurrency(plan.crossover.spread)} of spread) in {plan.tax_year} with{" "}
                        <span className="font-semibold">$0 additional AMT</span>.
                      </p>
                      <p className="mt-0.5 text-xs text-muted-foreground">
                        Binding constraint: {plan.crossover.binding === "federal" ? "federal AMT" : "California AMT"} ·
                        at {formatCurrency(plan.share_price)}/share vs {formatCurrency(plan.strike_price)} strike ·
                        {" "}{plan.exercisable_quantity.toLocaleString()} exercisable
                      </p>
                    </div>
                  )}

                  {/* Quantity + curve */}
                  <div className="space-y-2 rounded-xl border p-4">
                    <div className="flex flex-wrap items-center gap-3">
                      <label className="flex items-center gap-2 text-sm">
                        Exercise
                        <Input
                          type="number"
                          min="0"
                          max={plan.exercisable_quantity}
                          aria-label="Shares to exercise"
                          value={qty}
                          onChange={(e) => setQuantity(Math.max(0, Math.min(plan.exercisable_quantity, Number(e.target.value))))}
                          className="h-8 w-28 tabular-nums"
                        />
                        shares
                      </label>
                      <input
                        type="range"
                        min="0"
                        max={plan.exercisable_quantity}
                        step={Math.max(1, Math.round(plan.exercisable_quantity / 200))}
                        aria-label="Shares to exercise slider"
                        value={qty}
                        onChange={(e) => setQuantity(Number(e.target.value))}
                        className="min-w-40 flex-1 accent-primary"
                      />
                      <span className={cn("text-xs", isPending && "opacity-50")}>
                        marginal rate on next share:{" "}
                        <span className="font-medium tabular-nums">{(plan.simulation.marginal_rate_next_share * 100).toFixed(0)}%</span>
                      </span>
                    </div>

                    <TaxCurve plan={plan} />

                    <div className={cn("grid grid-cols-2 gap-3 pt-1 sm:grid-cols-4", isPending && "opacity-50")}>
                      <Stat label="Exercise cost" value={formatCurrency(plan.simulation.exercise_cost)} />
                      <Stat label="Federal AMT" value={formatCurrency(plan.simulation.federal_amt)} />
                      <Stat label="California AMT" value={formatCurrency(plan.simulation.california_amt)} />
                      <Stat label="Total cash needed" value={formatCurrency(plan.simulation.total_cash_needed)} strong />
                    </div>
                  </div>

                  {/* NSO under-withholding */}
                  {plan.nso_gap && plan.nso_gap.total_gap > 0 && (
                    <div className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/10 px-3 py-2 text-sm">
                      <TriangleAlert size={15} className="mt-0.5 shrink-0 text-warning" />
                      <p>
                        NSO withholding gap: payroll withholds at flat rates, but this exercise is likely{" "}
                        <span className="font-medium">{formatCurrency(plan.nso_gap.total_gap)}</span> under-withheld
                        (federal {formatCurrency(plan.nso_gap.federal_gap)} + CA {formatCurrency(plan.nso_gap.california_gap)}).
                      </p>
                    </div>
                  )}

                  {/* Scenarios */}
                  {isIso && (
                    <div className="grid gap-3 sm:grid-cols-3">
                      <ScenarioCard title="Exercise & hold" s={plan.scenarios.hold} />
                      <ScenarioCard title="Sell same year" s={plan.scenarios.same_year_sale} subtitle="Disqualifying — no AMT" />
                      <ScenarioCard title="Qualifying sale" s={plan.scenarios.qualifying_sale} subtitle="Hold 1yr+ / 2yr from grant" />
                    </div>
                  )}

                  {/* Safe harbor + escape hatch */}
                  <div className="space-y-1.5 rounded-xl border p-4 text-sm">
                    <SafeHarborLine label="Federal" sh={plan.safe_harbor.federal} />
                    <SafeHarborLine label="California" sh={plan.safe_harbor.california} />
                    {isIso && (
                      <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                        <CalendarClock size={12} />
                        Escape hatch: selling exercised shares by {formatDate(plan.escape_hatch_deadline)} erases the AMT adjustment entirely.
                      </p>
                    )}
                  </div>

                  {/* Stress panel */}
                  {isIso && qty > 0 && (
                    <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4">
                      <div className="flex flex-wrap items-center gap-2 text-sm">
                        <span className="font-medium">Downside:</span>
                        if the share price falls
                        <Select
                          aria-label="Stress drop percent"
                          value={String(dropPct)}
                          onChange={(e) => setDropPct(Number(e.target.value))}
                          wrapperClassName="w-24"
                          className="h-7 text-xs"
                        >
                          {[30, 50, 60, 80].map((p) => <option key={p} value={p}>{p}%</option>)}
                        </Select>
                        after Dec 31
                      </div>
                      <p className={cn("mt-1.5 text-sm", isPending && "opacity-50")}>
                        You would still owe <span className="font-semibold">{formatCurrency(plan.stress.tax_still_owed)}</span> in
                        AMT on shares then worth {formatCurrency(plan.stress.share_value_after)} — with the
                        exercise cost, you'd be <span className="font-semibold text-destructive">{formatCurrency(plan.stress.underwater)}</span> underwater.
                        AMT locks in at the exercise-date value no matter what happens after year end.
                      </p>
                    </div>
                  )}

                  {/* Assumptions footer */}
                  <div className="space-y-1 border-t pt-3 text-xs text-muted-foreground">
                    <p>
                      Tax tables: federal {plan.tax_year} ({plan.figures_status.federal}) · California ({plan.figures_status.state}
                      {plan.figures_status.state === "projected" && " — FTB publishes final figures in the fall"}).
                    </p>
                    <p>Not modeled: {plan.exclusions.join("; ")}.</p>
                    <p className="font-medium">
                      These are scenario estimates under the assumptions above — not tax advice. Confirm with a professional before acting.
                    </p>
                  </div>
                </>
              )}
            </>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ── Pieces ────────────────────────────────────────────────────────────────────

function Stat({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className={cn("tabular-nums", strong ? "text-sm font-semibold" : "text-sm")}>{value}</p>
    </div>
  );
}

function ScenarioCard({ title, s, subtitle }: { title: string; s?: ExercisePlanScenario; subtitle?: string }) {
  if (!s) return null;
  // Two shapes: flat {federal, california} for single-year scenarios, or
  // {exercise_year, sale_year} for the qualifying path. Totals are client-side.
  const twoYear = s.exercise_year && s.sale_year;
  const fed = twoYear ? s.exercise_year!.federal + s.sale_year!.federal : s.federal ?? 0;
  const ca = twoYear ? s.exercise_year!.california + s.sale_year!.california : s.california ?? 0;
  return (
    <div className="rounded-xl border p-3">
      <p className="text-sm font-medium">{title}</p>
      {subtitle && <p className="text-xs text-muted-foreground">{subtitle}</p>}
      <p className="mt-1.5 text-lg font-semibold tabular-nums">{formatCurrency(fed + ca)}</p>
      <p className="text-xs text-muted-foreground">
        fed {formatCurrency(fed)} · CA {formatCurrency(ca)}
      </p>
      {twoYear && (
        <p className="text-xs text-muted-foreground">
          exercise yr {formatCurrency(s.exercise_year!.federal + s.exercise_year!.california)} ·
          sale yr {formatCurrency(s.sale_year!.federal + s.sale_year!.california)}
        </p>
      )}
      {s.proceeds != null && (
        <p className="text-xs text-muted-foreground">proceeds {formatCurrency(s.proceeds)}</p>
      )}
      {s.note && <p className="mt-1 text-xs text-muted-foreground">{s.note}</p>}
    </div>
  );
}

function SafeHarborLine({ label, sh }: { label: string; sh: ExercisePlan["safe_harbor"]["federal"] }) {
  const tone =
    sh.status === "covered" ? "text-positive"
    : sh.status === "uncovered" || sh.status === "unavailable" ? "text-warning"
    : "text-muted-foreground";
  return (
    <p>
      <span className="font-medium">{label} safe harbor:</span>{" "}
      <span className={tone}>
        {sh.status === "covered" && <>covered — the tax is due April 15; set aside {sh.set_aside != null ? formatCurrency(sh.set_aside) : "the AMT amount"}.</>}
        {sh.status === "uncovered" && <>not covered — estimated payments likely needed{sh.required_annual != null && <> (target {formatCurrency(sh.required_annual)})</>}.</>}
        {sh.status === "unavailable" && <>unavailable{sh.note ? ` — ${sh.note}` : ""}.</>}
        {sh.status === "unknown" && <>enter last year's total tax and AGI in the profile to check.</>}
      </span>
    </p>
  );
}

/** Inline SVG tax curve: total incremental AMT vs shares exercised, with the
 * crossover marked. Self-contained (the shared chart kit is time-series-
 * oriented); colors via currentColor + CSS variables only. */
function TaxCurve({ plan }: { plan: ExercisePlan }) {
  const W = 560, H = 120, PAD = 8;
  const points = plan.curve;
  if (points.length < 2) return null;
  const maxQ = points[points.length - 1].quantity || 1;
  const maxT = Math.max(...points.map((p) => p.total), 1);
  const x = (q: number) => PAD + (q / maxQ) * (W - 2 * PAD);
  const y = (t: number) => H - PAD - (t / maxT) * (H - 2 * PAD);
  const path = points.map((p, i) => `${i === 0 ? "M" : "L"}${x(p.quantity).toFixed(1)},${y(p.total).toFixed(1)}`).join(" ");
  const qty = plan.simulation.quantity;

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      className="h-28 w-full"
      role="img"
      aria-label="Tax owed versus shares exercised"
    >
      <line x1={PAD} y1={H - PAD} x2={W - PAD} y2={H - PAD} stroke="var(--color-border)" strokeWidth="1" />
      <path d={path} fill="none" stroke="var(--color-primary)" strokeWidth="2" />
      {plan.crossover && plan.crossover.shares > 0 && (
        <g>
          <line x1={x(plan.crossover.shares)} y1={PAD} x2={x(plan.crossover.shares)} y2={H - PAD}
            stroke="var(--color-positive)" strokeWidth="1" strokeDasharray="3 3" />
          <text x={Math.min(x(plan.crossover.shares) + 4, W - 90)} y={PAD + 10}
            fontSize="10" fill="var(--color-muted-foreground)">
            $0 AMT: {plan.crossover.shares.toLocaleString()}
          </text>
        </g>
      )}
      <circle cx={x(qty)} cy={y(interp(points, qty))} r="3.5" fill="var(--color-primary)" />
    </svg>
  );
}

function interp(points: { quantity: number; total: number }[], q: number): number {
  const after = points.findIndex((p) => p.quantity >= q);
  if (after <= 0) return points[Math.max(after, 0)]?.total ?? 0;
  const a = points[after - 1], b = points[after];
  const f = b.quantity === a.quantity ? 0 : (q - a.quantity) / (b.quantity - a.quantity);
  return a.total + f * (b.total - a.total);
}
