import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { StatRibbon } from "@/components/StatRibbon";
import { KeyValueTable } from "@/components/ui/key-value-table";
import {
  ChartLabel, ChartCard, LineChart, BarChart, TimeframeSelector, type Timeframe,
} from "@/components/charts";
import { InvestmentTransactionTable } from "@/components/InvestmentTransactionTable";
import { HoldingsTable, type HoldingRow } from "@/components/HoldingsTable";
import { cn, formatCurrency } from "@/lib/utils";
import { SectionLoading, TableWithAside } from "./SectionLayout";

export function CryptoSection({ timeframe }: { timeframe: Timeframe }) {
  const { from, to } = timeframe;
  const { data, isLoading, refetch, isPlaceholderData } = useQuery({
    ...queries.crypto({ from, to }),
    placeholderData: keepPreviousData,
  });

  if (isLoading) return <SectionLoading />;
  if (!data) return <ErrorState title="Failed to load crypto" onRetry={() => refetch()} />;

  const { summary, positions, monthly_volume, cumulative_invested, top_assets, by_account, recent } = data;

  const glPositive = summary.unrealized_gl >= 0;

  const monthlyData = monthly_volume.map(([date, v]) => ({ month: date.slice(0, 7), value: v }));
  const cumulativeData = cumulative_invested.map(([date, v]) => ({ date: date.slice(0, 10), value: v }));

  return (
    <div className={cn("@container flex flex-col", isPlaceholderData && "opacity-50 transition-opacity")}>
      <PageHeader
        title="Crypto"
        subtitle={positions.length > 0 ? `${positions.length} asset${positions.length !== 1 ? "s" : ""}` : undefined}
      />

      <StatRibbon borderTop={false} stats={[
        { label: "Total Value",    value: formatCurrency(summary.total_value, true) },
        { label: "Unrealized G/L", value: formatCurrency(summary.unrealized_gl, true), highlight: glPositive ? "positive" : "negative" },
        { label: "Total Invested", value: formatCurrency(summary.total_invested, true) },
        { label: "YTD Invested",   value: formatCurrency(summary.ytd_invested, true) },
        { label: "Purchases",      value: summary.buy_count.toLocaleString() },
      ]} />

      <div className="p-6">
        <div className="grid gap-4 lg:grid-cols-2">
          <ChartCard
            title="Cumulative Invested"
            control={<TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />}
          >
            <LineChart
              data={cumulativeData}
              series={[{ key: "value", label: "Invested" }]}
              xKey="date"
              height={160}
            />
          </ChartCard>

          <ChartCard title="Monthly Purchased">
            <BarChart
              data={monthlyData}
              series={[{ key: "value", label: "Purchased" }]}
              height={160}
            />
          </ChartCard>
        </div>
      </div>

      {positions.length > 0 && (
        <div className="border-t">
          <HoldingsTable
            holdings={positions.map((p): HoldingRow => ({
              id:                p.id,
              security_id:       p.security_id,
              ticker:            p.ticker,
              name:              p.name,
              cusip:             p.cusip,
              label:             p.label,
              quantity:          p.quantity,
              price:             p.price,
              market_value:      p.market_value,
              cost_basis:        p.cost_basis,
              unrealized_gl:     p.unrealized_gl,
              unrealized_gl_pct: p.unrealized_gl_pct,
              asset_class:       "Crypto",
              est_annual_income: null,
              dividend_yield:    null,
              as_of_date:        null,
            }))}
          />
        </div>
      )}

      <TableWithAside
        table={<InvestmentTransactionTable transactions={recent} showSecurity />}
        aside={<>
          {top_assets.length > 0 && (
            <div>
              <ChartLabel>Top Assets</ChartLabel>
              <KeyValueTable
                header={{ label: "Ticker", value: "Invested" }}
                rows={top_assets.map((s) => ({
                  key: s.ticker,
                  label: <><p className="font-medium">{s.ticker}</p><p className="text-xs text-muted-foreground truncate">{s.name}</p></>,
                  value: formatCurrency(s.total),
                }))}
              />
            </div>
          )}

          {Object.keys(by_account).length > 0 && (
            <div>
              <ChartLabel>By Account</ChartLabel>
              <KeyValueTable
                mutedLabels
                rows={Object.entries(by_account).map(([name, value]) => ({
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
