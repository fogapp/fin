import { useState, useMemo } from "react";
import { useQuery, useQueries } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { StatRibbon } from "@/components/StatRibbon";
import { Card, CardContent } from "@/components/ui/card";
import { Tabs } from "@/components/ui/tabs";
import { ChartLabel, LineChart, BarChart, PieChart, useChartTheme } from "@/components/charts";
import { BenchmarkCombobox } from "@/components/BenchmarkCombobox";
import { SecurityPriceChart } from "@/components/SecurityPriceChart";
import { cutoffFor, type Period, type PriceData } from "@/lib/pricePeriods";
import { HoldingsTable, type HoldingRow } from "@/components/HoldingsTable";
import { cn, formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import { SectionLoading, TableWithAside } from "./SectionLayout";
import type { BenchmarkEntry } from "@/api/types";

// For each portfolio date, find the nearest benchmark price on or before that date.
function alignBenchmark(portfolioDates: string[], benchmark: BenchmarkEntry): Map<string, number> {
  const sorted = [...benchmark.prices].sort(([a], [b]) => a.localeCompare(b));
  const result = new Map<string, number>();
  let bi = 0;
  for (const date of portfolioDates) {
    while (bi + 1 < sorted.length && sorted[bi + 1][0] <= date) bi++;
    if (bi < sorted.length && sorted[bi][0] <= date) result.set(date, sorted[bi][1]);
  }
  return result;
}

export function PortfolioSection() {
  const theme = useChartTheme();
  const [period, setPeriod] = useState<Period>("1Y");
  const [comparisons, setComparisons] = useState<string[]>([]);

  const { data: portfolio,   isLoading: loadingPortfolio, refetch: refetchPortfolio } = useQuery(queries.portfolio());
  const { data: sells,       isLoading: loadingSells,     refetch: refetchSells     } = useQuery(queries.sells(undefined, { limit: 1 }));
  const { data: dividends,   isLoading: loadingDividends, refetch: refetchDividends } = useQuery(queries.dividends(undefined, { limit: 1 }));
  const { data: benchmarkMeta }                                                      = useQuery(queries.benchmarks());
  // TWR/XIRR over the selected chart period ("MAX" → backend's 10y cap).
  const { data: performance } = useQuery(
    queries.portfolioPerformance(cutoffFor(period) ?? "2000-01-01"),
  );

  // One cached query per selected comparison ticker
  const priceQueries = useQueries({
    queries: comparisons.map((symbol) => queries.benchmarkPrices(symbol)),
  });

  // Map symbol → color (stable by position: portfolio holds slot 1, comparisons
  // take slots 2+ in fixed order — never cycled)
  const comparisonColors: Record<string, string> = Object.fromEntries(
    comparisons.map((sym, i) => [sym, theme.series[i + 1] ?? theme.neutral])
  );

  const addComparison    = (sym: string) => setComparisons((prev) => prev.includes(sym) ? prev : [...prev, sym]);
  const removeComparison = (sym: string) => setComparisons((prev) => prev.filter((s) => s !== sym));

  const compareMode = comparisons.length > 0;
  const cutoff = cutoffFor(period);

  // [date, value] pairs for SecurityPriceChart (no volume)
  const portfolioPriceData = useMemo<PriceData>(() => {
    if (!portfolio) return [];
    return Object.entries(portfolio.portfolio_history)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([date, value]) => [date, value]);
  }, [portfolio]);

  // Filtered history for the comparison chart (needs {date, value} objects)
  const historyData = useMemo(() => {
    if (!portfolio) return [];
    const entries = Object.entries(portfolio.portfolio_history).sort(([a], [b]) => a.localeCompare(b));
    const filtered = cutoff ? entries.filter(([d]) => d >= cutoff) : entries;
    return filtered.map(([date, value]) => ({ date, value }));
  }, [portfolio, cutoff]);

  // Stabilize price data so compareChartData memo doesn't re-run on every render
  // (useQueries returns a new array reference every render)
  const priceDataKey = priceQueries.map(q => q.dataUpdatedAt).join(",");
  const priceQueryData = useMemo(
    () => priceQueries.map(q => q.data),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- priceQueries is a new array every render; priceDataKey changes exactly when any query's data does
    [priceDataKey]
  );

  const compareChartData = useMemo(() => {
    if (!compareMode || historyData.length === 0) return [];
    const portfolioStart = historyData[0].value;
    const dates = historyData.map(d => d.date);

    const alignedMaps: Record<string, Map<string, number>> = {};
    const benchStarts: Record<string, number> = {};
    for (const entry of priceQueryData) {
      if (!entry || entry.prices.length === 0) continue;
      const map = alignBenchmark(dates, entry);
      alignedMaps[entry.symbol] = map;
      const firstPrice = map.get(dates[0]);
      if (firstPrice) benchStarts[entry.symbol] = firstPrice;
    }

    return historyData.map(({ date, value }) => {
      const point: Record<string, number | string> = {
        date,
        Portfolio: portfolioStart > 0 ? +((value / portfolioStart - 1) * 100).toFixed(2) : 0,
      };
      for (const symbol of comparisons) {
        const price = alignedMaps[symbol]?.get(date);
        const start = benchStarts[symbol];
        if (price && start) point[symbol] = +((price / start - 1) * 100).toFixed(2);
      }
      return point;
    });
  }, [compareMode, historyData, comparisons, priceQueryData]);

  const glData = useMemo(() => {
    if (!portfolio) return [];
    return [...portfolio.positions]
      .filter(p => p.cost_basis > 0 && p.security_ticker)
      .sort((a, b) => b.unrealized_gl - a.unrealized_gl)
      .slice(0, 15);
  }, [portfolio]);

  if (loadingPortfolio || loadingSells || loadingDividends) return <SectionLoading />;
  if (!portfolio || !sells || !dividends) {
    return (
      <ErrorState
        title="Failed to load portfolio"
        onRetry={() => { refetchPortfolio(); refetchSells(); refetchDividends(); }}
      />
    );
  }

  const { summary, positions, by_asset_class } = portfolio;
  const unrealized     = summary.unrealized_gl;
  const realizedNet    = sells.totals.realized_net;
  const divLifetime    = dividends.totals.lifetime;
  const totalReturn    = unrealized + realizedNet + divLifetime;
  const costBasis      = summary.total_cost_basis;
  const totalReturnPct = costBasis > 0 ? (totalReturn / costBasis) * 100 : 0;
  const glPositive     = unrealized >= 0;
  const retPositive    = totalReturn >= 0;

  const allocationData = Object.entries(by_asset_class).map(([name, value]) => ({ name, value }));

  return (
    <div className="@container flex flex-col">
      <PageHeader
        title="Portfolio"
        subtitle={portfolio.as_of_date ? `as of ${formatDate(portfolio.as_of_date)}` : undefined}
      />

      <StatRibbon borderTop={false} stats={[
        { label: "Total Value",    value: formatCurrency(summary.total_value, true) },
        { label: "Cost Basis",     value: formatCurrency(costBasis, true) },
        { label: "Unrealized G/L", value: formatCurrency(unrealized, true), highlight: glPositive ? "positive" : "negative" },
        {
          label: "Total Return",
          value: `${formatCurrency(totalReturn, true)}  (${retPositive ? "+" : ""}${totalReturnPct.toFixed(1)}%)`,
          highlight: retPositive ? "positive" : "negative",
          dividerBefore: true,
        },
        { label: "Realized G/L",       value: formatCurrency(realizedNet, true) },
        { label: "Dividends",          value: formatCurrency(divLifetime, true) },
        { label: "Est. Annual Income", value: formatCurrency(summary.est_annual_income) },
        ...(performance?.twr_pct != null ? [{
          label: `TWR (${period})`,
          value: `${performance.twr_pct >= 0 ? "+" : ""}${performance.twr_pct.toFixed(2)}%`,
          highlight: performance.twr_pct >= 0 ? "positive" as const : "negative" as const,
          dividerBefore: true,
        }] : []),
        ...(performance?.xirr_pct != null ? [{
          label: `XIRR (${period})`,
          value: `${performance.xirr_pct >= 0 ? "+" : ""}${performance.xirr_pct.toFixed(2)}%`,
          highlight: performance.xirr_pct >= 0 ? "positive" as const : "negative" as const,
        }] : []),
      ]} />

      <div className="p-6">
        <div className="grid gap-6 lg:grid-cols-[2fr_1fr]">
          {/* Portfolio value / comparison chart */}
          {compareMode ? (
            <div>
              <div className="mb-2 flex flex-wrap items-center gap-2">
                <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">% Return vs Benchmark</span>
                <BenchmarkCombobox selected={comparisons} onAdd={addComparison} onRemove={removeComparison}
                  suggestions={benchmarkMeta ?? []} colors={comparisonColors} />
              </div>
              <LineChart
                data={compareChartData}
                series={[
                  { key: "Portfolio", label: "Portfolio" },
                  // Same entity→color assignment as the combobox chips
                  ...comparisons.map((symbol) => ({ key: symbol, label: symbol, color: comparisonColors[symbol] })),
                ]}
                xKey="date"
                height={230}
                xTickFormat={(v) => period === "MAX" ? v.slice(0, 4) : v.slice(0, 7)}
                yFormat={(v) => `${v >= 0 ? "+" : ""}${v.toFixed(1)}%`}
                valueFormat={(v) => `${v >= 0 ? "+" : ""}${v.toFixed(2)}%`}
                labelFormat={(l) => formatDate(l)}
              />
              {/* Period tabs row below comparison chart */}
              <div className="mt-2 flex items-center justify-end gap-2">
                <Tabs<Period>
                  size="sm"
                  value={period}
                  onChange={setPeriod}
                  options={(["YTD", "1Y", "MAX"] as Period[]).map((p) => ({ value: p, label: p }))}
                />
              </div>
            </div>
          ) : (
            <SecurityPriceChart
              data={portfolioPriceData}
              period={period}
              onPeriodChange={setPeriod}
              yFormatter={(v) => `$${v >= 1000 ? `${(v / 1000).toFixed(0)}k` : v.toFixed(0)}`}
              valueFormatter={formatCurrency}
              toolbarLeft={
                <BenchmarkCombobox selected={comparisons} onAdd={addComparison} onRemove={removeComparison}
                  suggestions={benchmarkMeta ?? []} colors={comparisonColors} />
              }
            />
          )}

          <div>
            <ChartLabel>Asset Allocation</ChartLabel>
            <PieChart data={allocationData} height={230} />
          </div>
        </div>
      </div>

      <TableWithAside
        table={
          <HoldingsTable
            exportDataset="portfolio"
            holdings={positions.map((p): HoldingRow => ({
              id:                p.id,
              security_id:       p.security_id,
              ticker:            p.security_ticker,
              name:              p.security_name,
              cusip:             p.security_cusip,
              label:             p.security_label,
              quantity:          p.quantity,
              price:             p.price,
              market_value:      p.market_value,
              cost_basis:        p.cost_basis,
              unrealized_gl:     p.unrealized_gl,
              unrealized_gl_pct: p.unrealized_gl_pct,
              asset_class:       p.asset_class,
              est_annual_income: p.est_annual_income,
              dividend_yield:    p.dividend_yield,
              as_of_date:        p.as_of_date,
            }))}
          />
        }
        aside={<>
          <div>
            <ChartLabel>Realized G/L</ChartLabel>
            <Card>
              <CardContent className="p-0">
                <table className="w-full text-sm">
                  <tbody className="divide-y">
                    {[
                      { label: "Short-term", value: sells.totals.realized_short },
                      { label: "Long-term",  value: sells.totals.realized_long },
                      { label: "Net",        value: sells.totals.realized_net, bold: true },
                    ].map(({ label, value, bold }) => (
                      <tr key={label}>
                        <td className={cn("px-4 py-2.5 text-muted-foreground", bold && "font-medium text-foreground")}>{label}</td>
                        <td className={cn("px-4 py-2.5 text-right tabular-nums", moneyColor(value), bold && "font-semibold")}>
                          {value >= 0 ? "+" : ""}{formatCurrency(value)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </CardContent>
            </Card>
          </div>

          <div>
            <ChartLabel>Dividend Income</ChartLabel>
            <Card>
              <CardContent className="p-0">
                <table className="w-full text-sm">
                  <tbody className="divide-y">
                    {[
                      { label: "YTD",            value: dividends.totals.ytd },
                      { label: "Last 12 months", value: dividends.totals.last_12mo },
                      { label: "Lifetime",       value: dividends.totals.lifetime },
                    ].map(({ label, value }) => (
                      <tr key={label}>
                        <td className="px-4 py-2.5 text-muted-foreground">{label}</td>
                        <td className="px-4 py-2.5 text-right tabular-nums">{formatCurrency(value)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </CardContent>
            </Card>
          </div>

          {glData.length > 0 && (
            <div>
              <ChartLabel>G/L by Position</ChartLabel>
              <BarChart
                data={glData}
                series={[{ key: "unrealized_gl", label: "Unrealized G/L" }]}
                xKey="security_ticker"
                orientation="horizontal"
                diverging
                height={glData.length * 28 + 8}
              />
            </div>
          )}
        </>}
      />
    </div>
  );
}
