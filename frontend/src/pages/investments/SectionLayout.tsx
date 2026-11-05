import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon } from "@/components/StatRibbon";
import { InvestmentTransactionTable } from "@/components/InvestmentTransactionTable";
import { KeyValueTable } from "@/components/ui/key-value-table";
import { Skeleton } from "@/components/ui/skeleton";
import { ChartLabel, ChartCard, LineChart, BarChart } from "@/components/charts";
import { cn, formatCurrency } from "@/lib/utils";
import type { TopSecurity, InvestmentTransaction } from "@/api/types";

/**
 * Table with a 340px aside on the right. Tables can't shrink below their
 * min-content width (and an overflow-x wrapper would break the sticky thead),
 * so below 78rem of section width the aside stacks under the table instead.
 * Requires `@container` on the section root.
 */
export function TableWithAside({ table, aside }: { table: React.ReactNode; aside: React.ReactNode }) {
  return (
    <div className="flex min-h-0 flex-col border-t @min-[78rem]:flex-row">
      <div className="min-w-0 flex-1">{table}</div>
      <aside className="grid shrink-0 content-start gap-6 border-t px-6 py-6 @min-[48rem]:grid-cols-2 @min-[78rem]:w-[340px] @min-[78rem]:grid-cols-1 @min-[78rem]:border-l @min-[78rem]:border-t-0">
        {aside}
      </aside>
    </div>
  );
}

export function SectionLoading() {
  return (
    <div className="space-y-6 p-6">
      <Skeleton className="h-6 w-32" />
      <Skeleton className="h-10 rounded-xl" />
      <div className="grid gap-4 lg:grid-cols-2">
        <Skeleton className="h-40 rounded-xl" />
        <Skeleton className="h-40 rounded-xl" />
      </div>
      <div className="grid gap-6 lg:grid-cols-[1fr_260px]">
        <Skeleton className="h-64 rounded-xl" />
        <div className="space-y-4">
          <Skeleton className="h-48 rounded-xl" />
          <Skeleton className="h-32 rounded-xl" />
        </div>
      </div>
    </div>
  );
}

export function SectionLayout({ title, ribbon, barData, barKey, barLabel, lineData, lineKey, lineLabel, topSecurities, topLabel, byAccount, transactions, dimmed = false, control }: {
  title: string;
  ribbon: Parameters<typeof StatRibbon>[0]["stats"];
  barData: object[];
  barKey: string;
  barLabel: string;
  lineData: object[];
  lineKey: string;
  lineLabel: string;
  topSecurities: TopSecurity[];
  topLabel: string;
  byAccount: Record<string, number>;
  transactions: InvestmentTransaction[];
  /** Hold the previous render at reduced opacity while a new range loads. */
  dimmed?: boolean;
  /** Compact chrome for the primary chart card header (e.g. TimeframeSelector). */
  control?: React.ReactNode;
}) {
  return (
    <div className={cn("@container relative flex flex-col", dimmed && "opacity-50 transition-opacity")}>
      <PageHeader title={title} />
      <StatRibbon borderTop={false} stats={ribbon} />

      <div className="p-6">
        <div className="grid gap-4 lg:grid-cols-2">
          <ChartCard title={barLabel} control={control}>
            <BarChart
              data={barData}
              series={[{ key: barKey, label: barLabel }]}
              height={160}
            />
          </ChartCard>
          <ChartCard title={lineLabel}>
            <LineChart
              data={lineData}
              series={[{ key: lineKey, label: lineLabel }]}
              xKey="date"
              height={160}
            />
          </ChartCard>
        </div>
      </div>

      <TableWithAside
        table={<InvestmentTransactionTable transactions={transactions} showSecurity />}
        aside={<>
          {topSecurities.length > 0 && (
            <div>
              <ChartLabel>Top Securities</ChartLabel>
              <KeyValueTable
                header={{ label: "Ticker", value: topLabel }}
                rows={topSecurities.map((s, i) => ({
                  key: s.ticker ?? String(i),
                  label: s.ticker
                    ? <><p className="font-medium">{s.ticker}</p><p className="text-xs text-muted-foreground truncate">{s.name}</p></>
                    : <p className="truncate">{s.name ?? "—"}</p>,
                  value: formatCurrency(s.total),
                }))}
              />
            </div>
          )}

          {Object.keys(byAccount).length > 0 && (
            <div>
              <ChartLabel>By Account</ChartLabel>
              <KeyValueTable
                mutedLabels
                rows={Object.entries(byAccount).map(([name, value]) => ({
                  key: name,
                  label: name,
                  value: formatCurrency(value),
                }))}
              />
            </div>
          )}
        </>}
      />
    </div>
  );
}
