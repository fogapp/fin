import { Fragment, useMemo, useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import {
  ComposedChart, Area, Line,
  XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine,
} from "recharts";
import { ChevronDown } from "lucide-react";
import { queries } from "@/api/queries";
import type {
  NetWorthAccountRow, NetWorthData, NetWorthEquityRow, NetWorthGroup,
  NetWorthLoanRow, NetWorthPropertyRow,
} from "@/api/types";
import { usePageTimeframe } from "@/hooks/useTimeframeButtons";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { StatRibbon } from "@/components/StatRibbon";
import {
  ChartLabel, ChartCard, TimeframeSelector, TooltipShell, TooltipRow,
  isoDate, useChartTheme, type ChartTheme,
} from "@/components/charts";
import { cn, formatCurrency, formatDate, formatPercent, moneyColor } from "@/lib/utils";
import { categoryAxisProps, curveFor, valueAxisProps } from "@/components/charts/common";
import { ProjectionCard } from "./networth/ProjectionCard";

/** Fixed slot order — a group keeps its palette slot regardless of filters. */
const GROUPS: { key: NetWorthGroup; label: string; slot: number; liability: boolean }[] = [
  { key: "cash",        label: "Cash",         slot: 0, liability: false },
  { key: "investments", label: "Investments",  slot: 1, liability: false },
  { key: "crypto",      label: "Crypto",       slot: 2, liability: false },
  { key: "real_estate", label: "Real Estate",  slot: 3, liability: false },
  { key: "equity",      label: "Equity",       slot: 4, liability: false },
  { key: "credit",      label: "Credit Cards", slot: 5, liability: true },
  { key: "loans",       label: "Loans",        slot: 6, liability: true },
];

export function NetWorth() {
  const theme = useChartTheme();
  const timeframe = usePageTimeframe("net_worth", "net-worth-timeframe");
  const { data, isLoading, error, isPlaceholderData, refetch } = useQuery({
    ...queries.netWorth({ from: timeframe.from, to: timeframe.to }),
    placeholderData: keepPreviousData,
  });

  // Groups that never have a value are dropped from the chart and legend.
  const activeGroups = useMemo(
    () => GROUPS.filter((g) => data?.series.some((p) => p[g.key] !== 0)),
    [data?.series]
  );

  if (isLoading) return <LoadingState />;
  if (error || !data) return <ErrorState title="Failed to load net worth" message={(error as Error)?.message} onRetry={() => refetch()} />;

  const { stats } = data;
  // Month-granular ticks once the window spans more than ~13 months.
  const longSeries = data.series.length > 1 &&
    (Date.parse(data.series[data.series.length - 1].date) - Date.parse(data.series[0].date)) / 86_400_000 > 400;
  const hasData = [data.accounts, data.loans, data.properties, data.equity]
    .some((rows) => (rows ?? []).length > 0);

  return (
    <div className="flex flex-col">
      <PageHeader title="Net Worth" level={1} sticky />

      {!hasData ? (
        <EmptyState
          className="flex-1 py-16"
          title="No balance history yet"
          description="Net worth is built from account balances, investment positions, and loans. Connect accounts via Plaid or import a CSV, and history will accumulate from nightly balance snapshots."
        />
      ) : (
        <>
          <StatRibbon borderTop={false} stats={[
            { label: "Net Worth",   value: formatCurrency(stats.net_worth, true), change: stats.changes["1m"]?.pct },
            { label: "Assets",      value: formatCurrency(stats.assets, true) },
            { label: "Liabilities", value: formatCurrency(stats.liabilities, true) },
            ...activeGroups.map((g) => ({
              label: g.label,
              value: formatCurrency(g.liability ? -stats[g.key] : stats[g.key], true),
              dividerBefore: g.key === "cash",
            })),
            { label: "1M Change",  value: formatCurrency(stats.changes["1m"]?.amount, true),  change: stats.changes["1m"]?.pct,  dividerBefore: true },
            { label: "YTD Change", value: formatCurrency(stats.changes["ytd"]?.amount, true), change: stats.changes["ytd"]?.pct },
            { label: "1Y Change",  value: formatCurrency(stats.changes["1y"]?.amount, true),  change: stats.changes["1y"]?.pct },
          ]} />

          <div className={cn("space-y-6 p-4 md:p-6", isPlaceholderData && "opacity-50 transition-opacity")}>
            <ChartCard
              title="Net Worth Over Time"
              control={(
                <TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />
              )}
            >
                  <ResponsiveContainer width="100%" height={300}>
                    <ComposedChart data={data.series} stackOffset="sign">
                      <XAxis
                        dataKey="date" {...categoryAxisProps(theme)}
                        tickFormatter={(v: string) => longSeries ? v.slice(0, 7) : v.slice(5)}
                        interval="preserveStartEnd" minTickGap={40}
                      />
                      <YAxis
                        {...valueAxisProps(theme)} width={52}
                        tickFormatter={(v: number) => formatCurrency(v, true)}
                      />
                      <Tooltip content={<SeriesTooltip groups={activeGroups} theme={theme} />} isAnimationActive={false} />
                      <ReferenceLine y={0} stroke={theme.axis} />
                      {activeGroups.map((g) => (
                        <Area
                          key={g.key} dataKey={g.key} name={g.label}
                          stackId={g.liability ? "liabilities" : "assets"}
                          type={curveFor(data.series.length)} stroke={theme.series[g.slot]} fill={theme.series[g.slot]}
                          fillOpacity={0.25} strokeWidth={1} dot={false}
                        />
                      ))}
                      <Line dataKey="net" name="Net" type={curveFor(data.series.length)} dot={false}
                        stroke="var(--color-foreground)" strokeWidth={2} />
                    </ComposedChart>
                  </ResponsiveContainer>
                  <div className="mt-2 flex flex-wrap justify-center gap-x-4 gap-y-1 text-tiny text-muted-foreground">
                    {activeGroups.map((g) => (
                      <span key={g.key} className="flex items-center gap-1">
                        <span className="h-0.5 w-3 rounded-full" style={{ background: theme.series[g.slot] }} />
                        {g.label}
                      </span>
                    ))}
                    <span className="flex items-center gap-1">
                      <span className="h-0.5 w-3 rounded bg-foreground" />
                      Net
                    </span>
                  </div>
            </ChartCard>

            <ProjectionCard />

            <BalanceSheet data={data} />
          </div>
        </>
      )}
    </div>
  );
}

// ── Balance sheet ─────────────────────────────────────────────────────────────
// Assets over liabilities, grouped the same way the chart stacks them, with a
// subtotal per group and the range's start value beside today's so every line
// carries its own change. Group order and dot color come from GROUPS, so a
// bucket reads identically here and in the chart above.

/** Column headers for the window's start value and its end value — the end
 *  is only worth naming when the window stops short of today. */
function sheetHeaders(data: NetWorthData): { start: string; end: string } {
  const today = isoDate();
  return {
    start: data.from ? formatDate(data.from) : "Start",
    end: data.to && data.to < today ? formatDate(data.to) : "Value",
  };
}

interface SheetRow {
  id: string;
  name: string;
  detail: string | null;
  value: number;
  /** Null when the line had no data at the start of the range. */
  start: number | null;
}

interface SheetGroup {
  key: NetWorthGroup;
  label: string;
  slot: number;
  liability: boolean;
  rows: SheetRow[];
  value: number;
  start: number | null;
  /** Some member's history begins mid-window, so the baseline is incomplete
   *  and a percent off it would be fiction. Dollars still add up. */
  partial: boolean;
}

function accountRow(account: NetWorthAccountRow): SheetRow {
  return {
    id: account.id,
    name: account.name,
    detail: [account.broker, account.account_type].filter(Boolean).join(" · ") || null,
    value: account.value,
    start: account.start_value,
  };
}

/** Gross value — the mortgage financing it is listed under Loans. */
function propertyRow(property: NetWorthPropertyRow): SheetRow {
  const mortgage = property.mortgage_balance != null
    ? `${formatCurrency(property.equity, true)} equity · ${formatCurrency(property.mortgage_balance, true)} mortgage`
    : "No mortgage";
  return {
    id: property.id,
    name: property.name,
    detail: [property.address, mortgage].filter(Boolean).join(" · "),
    value: property.value,
    start: property.start_value,
  };
}

/** Vested value unless the household counts unvested grants too. */
function equityRow(company: NetWorthEquityRow): SheetRow {
  const scope = company.include_unvested
    ? "vested + unvested"
    : company.unvested_value > 0
      ? `vested · ${formatCurrency(company.unvested_value, true)} unvested excluded`
      : "fully vested";
  return {
    id: company.id,
    name: company.name,
    detail: [company.ticker ?? (company.public_company ? null : "Private"), scope].filter(Boolean).join(" · "),
    value: company.value,
    start: company.start_value,
  };
}

function loanRow(loan: NetWorthLoanRow): SheetRow {
  return {
    id: loan.id,
    name: loan.name,
    detail: [loan.lender, loan.loan_type].filter(Boolean).join(" · ") || null,
    value: loan.value,
    start: loan.start_value,
  };
}

/** Groups larger than this start collapsed — a 30-wallet Investments group
 *  would otherwise bury every other line on the sheet. */
const AUTO_COLLAPSE_OVER = 5;

function BalanceSheet({ data }: { data: NetWorthData }) {
  const theme = useChartTheme();
  const [toggled, setToggled] = useState<Set<NetWorthGroup>>(new Set());

  // A response cached from before an API change arrives without the newer
  // collections, so every list is read defensively — a payload skew should
  // cost a section, not white-screen the page.
  const groups: SheetGroup[] = GROUPS.map((g) => {
    const rows: SheetRow[] = (data.accounts ?? []).filter((a) => a.group === g.key).map(accountRow);
    if (g.key === "real_estate") rows.push(...(data.properties ?? []).map(propertyRow));
    if (g.key === "equity") rows.push(...(data.equity ?? []).map(equityRow));
    if (g.key === "loans") rows.push(...(data.loans ?? []).map(loanRow));
    rows.sort((a, b) => Math.abs(b.value) - Math.abs(a.value));

    const known = rows.filter((r) => r.start != null);
    return {
      ...g,
      rows,
      value: rows.reduce((sum, r) => sum + r.value, 0),
      start: known.length === 0 ? null : known.reduce((sum, r) => sum + (r.start ?? 0), 0),
      partial: known.length !== rows.length,
    };
  }).filter((g) => g.rows.length > 0);

  // Default open/closed by size, with an explicit click flipping that default.
  const expanded = new Set(
    groups
      .filter((g) => (g.rows.length <= AUTO_COLLAPSE_OVER) !== toggled.has(g.key))
      .map((g) => g.key)
  );
  const toggle = (key: NetWorthGroup) =>
    setToggled((prev) => {
      const next = new Set(prev);
      if (!next.delete(key)) next.add(key);
      return next;
    });

  const assets      = groups.filter((g) => !g.liability);
  const liabilities = groups.filter((g) => g.liability);
  const sumValue = (list: SheetGroup[]) => list.reduce((sum, g) => sum + g.value, 0);
  const sumStart = (list: SheetGroup[]) =>
    list.every((g) => g.start == null) && list.length > 0
      ? null
      : list.reduce((sum, g) => sum + (g.start ?? 0), 0);
  const anyPartial = (list: SheetGroup[]) => list.some((g) => g.partial || g.start == null);

  const assetTotal     = sumValue(assets);
  const assetStart     = sumStart(assets);
  const liabilityTotal = sumValue(liabilities);
  const liabilityStart = sumStart(liabilities);
  const netValue = assetTotal - liabilityTotal;
  const netStart = assetStart == null && liabilityStart == null
    ? null
    : (assetStart ?? 0) - (liabilityStart ?? 0);
  const netPartial = anyPartial(assets) || anyPartial(liabilities);

  return (
    <div>
      <ChartLabel>Balance Sheet</ChartLabel>
      <Card>
        <CardContent className="overflow-x-auto p-0">
          <table className="w-full min-w-[640px] text-sm">
            <thead>
              <tr className="border-b text-xs text-muted-foreground">
                <th className="px-4 py-2 text-left font-medium">Account</th>
                <th className="hidden px-4 py-2 text-right font-medium sm:table-cell">Share</th>
                <th className="hidden px-4 py-2 text-right font-medium md:table-cell">{sheetHeaders(data).start}</th>
                <th className="px-4 py-2 text-right font-medium">Change</th>
                <th className="px-4 py-2 text-right font-medium">{sheetHeaders(data).end}</th>
              </tr>
            </thead>

            <SheetSection
              heading="Assets"
              groups={assets}
              denominator={assetTotal}
              theme={theme}
              total={{ label: "Total assets", value: assetTotal, start: assetStart, partial: anyPartial(assets) }}
              expanded={expanded}
              onToggle={toggle}
            />

            {liabilities.length > 0 && (
              <SheetSection
                heading="Liabilities"
                groups={liabilities}
                denominator={liabilityTotal}
                theme={theme}
                total={{ label: "Total liabilities", value: liabilityTotal, start: liabilityStart, partial: anyPartial(liabilities) }}
                expanded={expanded}
                onToggle={toggle}
              />
            )}

            <tbody className="border-t-2">
              <tr className="bg-muted/40">
                <td className="px-4 py-3 font-semibold" colSpan={2}>Net worth</td>
                <td className="hidden px-4 py-3 text-right tabular-nums text-muted-foreground md:table-cell">
                  {formatCurrency(netStart)}
                </td>
                <ChangeCell value={netValue} start={netStart} partial={netPartial} className="py-3 font-medium" />
                <td className="px-4 py-3 text-right text-base font-semibold tabular-nums">
                  {formatCurrency(netValue)}
                </td>
              </tr>
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  );
}

function SheetSection({ heading, groups, denominator, theme, total, expanded, onToggle }: {
  heading: string;
  groups: SheetGroup[];
  denominator: number;
  theme: ChartTheme;
  total: { label: string; value: number; start: number | null; partial: boolean };
  expanded: Set<string>;
  onToggle: (key: NetWorthGroup) => void;
}) {
  // Liabilities are stored as positive magnitudes; a growing balance is bad,
  // so their change tint is inverted against the asset side.
  const liability = groups[0]?.liability ?? false;

  return (
    <tbody className="border-t">
      <tr>
        <td colSpan={5} className="bg-muted/30 px-4 py-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          {heading}
        </td>
      </tr>

      {groups.map((group) => {
        const single = group.rows.length === 1;
        const open = single || expanded.has(group.key);

        return (
        <Fragment key={group.key}>
          <tr className="border-t">
            <td className="px-4 py-2 font-medium">
              <span className="flex items-center gap-2">
                <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: theme.series[group.slot] }} />
                {single ? (
                  group.label
                ) : (
                  <button
                    type="button"
                    onClick={() => onToggle(group.key)}
                    aria-expanded={open}
                    className="flex items-center gap-1 rounded font-medium hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                  >
                    {group.label}
                    <ChevronDown size={13} className={cn("text-muted-foreground transition-transform", !open && "-rotate-90")} />
                    <span className="text-xs font-normal text-muted-foreground">{group.rows.length}</span>
                  </button>
                )}
              </span>
              {/* A group of one is that one thing — name it here instead of
                  repeating the identical figures on an indented line. */}
              {single && (
                <span className="block pl-4 text-xs font-normal text-muted-foreground">
                  {[group.rows[0].name, group.rows[0].detail].filter(Boolean).join(" · ")}
                </span>
              )}
            </td>
            <td className="hidden px-4 py-2 text-right tabular-nums text-muted-foreground sm:table-cell">
              {denominator === 0 ? "—" : `${((group.value / denominator) * 100).toFixed(1)}%`}
            </td>
            <td className="hidden px-4 py-2 text-right tabular-nums text-muted-foreground md:table-cell">
              {formatCurrency(group.start)}
            </td>
            <ChangeCell value={group.value} start={group.start} partial={group.partial}
                        liability={liability} className="font-medium" />
            <td className="px-4 py-2 text-right font-semibold tabular-nums">{formatCurrency(group.value)}</td>
          </tr>

          {/* A group with one line is that line — don't repeat it underneath. */}
          {!single && open && group.rows.map((row) => (
            <tr key={row.id} className="text-muted-foreground">
              <td className="py-1.5 pl-10 pr-4">
                <p className="leading-tight text-foreground">{row.name}</p>
                {row.detail && <p className="text-xs">{row.detail}</p>}
              </td>
              <td className="hidden px-4 py-1.5 text-right text-xs tabular-nums sm:table-cell">
                {denominator === 0 ? "—" : `${((row.value / denominator) * 100).toFixed(1)}%`}
              </td>
              <td className="hidden px-4 py-1.5 text-right tabular-nums md:table-cell">{formatCurrency(row.start)}</td>
              <ChangeCell value={row.value} start={row.start} liability={liability} className="py-1.5" />
              <td className="px-4 py-1.5 text-right tabular-nums text-foreground">{formatCurrency(row.value)}</td>
            </tr>
          ))}
        </Fragment>
        );
      })}

      <tr className="border-t bg-muted/20">
        <td className="px-4 py-2 font-medium" colSpan={2}>{total.label}</td>
        <td className="hidden px-4 py-2 text-right tabular-nums text-muted-foreground md:table-cell">
          {formatCurrency(total.start)}
        </td>
        <ChangeCell value={total.value} start={total.start} partial={total.partial}
                    liability={liability} className="font-medium" />
        <td className="px-4 py-2 text-right font-semibold tabular-nums">{formatCurrency(total.value)}</td>
      </tr>
    </tbody>
  );
}

/** Change over the range: dollars, with the percent underneath when there's a
 *  complete baseline to measure it against. */
function ChangeCell({ value, start, liability = false, partial = false, className }: {
  value: number;
  start: number | null;
  liability?: boolean;
  partial?: boolean;
  className?: string;
}) {
  const change = value - (start ?? 0);
  // The percent keeps its true sign — a card balance down 20% reads "−20%" —
  // while the tint carries whether that move was good or bad. It's withheld
  // entirely when the baseline is missing or incomplete: a line whose history
  // starts mid-window hasn't grown infinitely, we just can't see back that far.
  const pct = start == null || start === 0 || partial
    ? null
    : ((value - start) / Math.abs(start)) * 100;
  const tint = change === 0 ? "" : moneyColor(liability ? -change : change);

  return (
    <td className={cn("px-4 py-2 text-right tabular-nums", tint, className)}>
      {change === 0 ? "—" : `${change > 0 ? "+" : ""}${formatCurrency(change)}`}
      {change !== 0 && pct != null && (
        <span className="block text-xs opacity-80">{formatPercent(pct)}</span>
      )}
    </td>
  );
}

// ── Chart tooltip ─────────────────────────────────────────────────────────────

interface TooltipProps {
  active?: boolean;
  payload?: ReadonlyArray<{ dataKey?: string; value?: number; payload?: Record<string, number> }>;
  label?: string;
  groups: typeof GROUPS;
  theme: ChartTheme;
}

function SeriesTooltip({ active, payload, label, groups, theme }: TooltipProps) {
  if (!active || !payload?.length) return null;
  const point = payload[0]?.payload ?? {};

  return (
    <TooltipShell label={formatDate(label)}>
      {groups.map((g) => {
        const value = point[g.key] ?? 0;
        if (value === 0) return null;
        return (
          <TooltipRow
            key={g.key}
            color={theme.series[g.slot]}
            name={g.label}
            value={formatCurrency(value)}
          />
        );
      })}
      <div className="mt-1 border-t pt-1">
        <TooltipRow name="Net Worth" value={formatCurrency(point.net)} strong />
      </div>
    </TooltipShell>
  );
}

// ── States ────────────────────────────────────────────────────────────────────

function LoadingState() {
  return (
    <div className="flex flex-col">
      <div className="flex h-14 items-center border-b px-6">
        <Skeleton className="h-5 w-28" />
      </div>
      <div className="h-12 bg-muted/50 border-b animate-pulse" />
      <div className="space-y-6 p-6">
        <Skeleton className="h-80 rounded-xl" />
        <div className="grid gap-6 lg:grid-cols-2">
          <Skeleton className="h-56 rounded-xl" />
          <Skeleton className="h-56 rounded-xl" />
        </div>
      </div>
    </div>
  );
}
