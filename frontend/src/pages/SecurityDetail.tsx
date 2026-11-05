import React, { useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import { useQuery, useQueries, useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowUp, ArrowDown, RefreshCw, Plus, ExternalLink } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { StatRibbon, type StatItem } from "@/components/StatRibbon";
import { InvestmentTransactionTable } from "@/components/InvestmentTransactionTable";
import { AddInvestmentTransactionDrawer } from "@/components/AddInvestmentTransactionDrawer";
import { InvestmentLotsEditor } from "@/components/InvestmentLotsEditor";
import { Card, CardContent } from "@/components/ui/card";
import { KeyValueTable } from "@/components/ui/key-value-table";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs } from "@/components/ui/tabs";
import { ErrorState } from "@/components/PageState";
import { ChartLabel, useChartTheme } from "@/components/charts";
import { AdvancedPriceChart } from "@/components/market/AdvancedPriceChart";
import { CANDLE_RANGES, type ComparisonSeries } from "@/components/market/ranges";
import { BenchmarkCombobox } from "@/components/BenchmarkCombobox";
import { SecurityConversionsCard } from "@/components/market/SecurityConversionsCard";
import { StalenessBadge } from "@/components/MarketBadges";
import { PageHeader } from "@/components/layout/PageHeader";
import { priceSourceLabel } from "@/lib/marketData";
import { cn, formatCurrency, formatCompactNumber, formatDate, moneyColor } from "@/lib/utils";
import type { SecurityOverview, NewsArticle, CandleRange } from "@/api/types";
import { invalidate, keys } from "@/api/keys";
import { useWatchSecurity } from "@/hooks/mutations/useWatchSecurity";

export function SecurityDetail() {
  const { id } = useParams<{ id: string }>();
  return <SecurityDetailContent id={id ?? ""} standalone />;
}

export function SecurityDetailContent({ id, standalone = false }: { id: string; standalone?: boolean }) {
  const qc = useQueryClient();
  const theme = useChartTheme();
  const [range, setRange] = useState<CandleRange>("1y");
  const [comparisons, setComparisons] = useState<string[]>([]);
  const [addingTx, setAddingTx] = useState(false);
  const [activeTab, setActiveTab] = useState<"transactions" | "lots" | "news">("transactions");

  const { data, isLoading, error, refetch } = useQuery(queries.security(id));
  const { data: candleData, isLoading: candlesLoading } = useQuery({
    ...queries.securityCandles(id, range),
    enabled: !!id,
  });
  const { data: accounts = [] } = useQuery(queries.accounts());
  const { data: benchmarkMeta } = useQuery(queries.benchmarks());
  const { data: newsData, isLoading: newsLoading } = useQuery({
    ...queries.securityNews(id),
    enabled: activeTab === "news" && !!id,
  });
  const securityUuid = data?.id ?? "";
  const { data: lots = [], refetch: refetchLots } = useQuery({
    ...queries.investmentLots(securityUuid),
    enabled: activeTab === "lots" && !!securityUuid,
  });

  // Comparison overlays: palette slot 0 stays with this security, so
  // comparisons take slots 1+ in add order (never cycled).
  const comparisonColors: Record<string, string> = Object.fromEntries(
    comparisons.map((sym, i) => [sym, theme.series[i + 1] ?? theme.neutral]),
  );
  const comparisonQueries = useQueries({
    queries: comparisons.map((symbol) => queries.benchmarkPrices(symbol)),
  });
  const comparisonDataKey = comparisonQueries.map((q) => q.dataUpdatedAt).join(",");
  const comparisonsKey = comparisons.join(",");
  const comparisonSeries = useMemo<ComparisonSeries[]>(
    () => comparisonQueries.flatMap((q) =>
      q.data && q.data.prices.length > 0
        ? [{ key: q.data.symbol, label: q.data.label, color: comparisonColors[q.data.symbol] ?? theme.neutral, prices: q.data.prices }]
        : [],
    ),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- comparisonQueries is a new array every render; the two keys change exactly when its data or membership does
    [comparisonDataKey, comparisonsKey, theme],
  );

  const refresh = useMutation({
    mutationFn: () => api.post(`/market/${id}/refresh`),
    onSuccess: () => invalidate(qc, queries.security(id).queryKey),
  });

  const { watch, unwatch } = useWatchSecurity();

  if (isLoading) return <LoadingState />;
  if (error || !data) return <ErrorState title="Security not found" onRetry={() => refetch()} />;

  const { position, dividends, latest_price, recent_transactions, overview } = data;

  const glPositive = (position?.unrealized_gl ?? 0) >= 0;

  // Range price change (header badge): last close vs the close just before
  // the visible window (falling back to the window's first close).
  const candles = candleData?.candles ?? [];
  const latestClose = latest_price?.close ?? candles.at(-1)?.c ?? null;
  const rangeBaseline = candleData?.prev_close ?? candles[0]?.c ?? null;
  const rangeAbsChange = rangeBaseline != null && latestClose != null ? latestClose - rangeBaseline : null;
  const rangePctChange = rangeBaseline != null && rangeAbsChange != null && rangeBaseline > 0
    ? (rangeAbsChange / rangeBaseline) * 100
    : null;
  const rangePositive = rangeAbsChange == null || rangeAbsChange >= 0;
  const rangeLabel = CANDLE_RANGES.find((r) => r.value === range)?.label ?? range;

  return (
    <div className="relative flex flex-col">
      <PageHeader
        title={data.display_name ?? data.name}
        level={2}
        back={standalone ? { to: "/market", label: "Back to market" } : undefined}
        actions={[
          { label: "Add transaction", icon: Plus, onSelect: () => setAddingTx(true) },
          {
            label: refresh.isPending ? "Refreshing…" : "Refresh prices",
            icon: RefreshCw,
            onSelect: () => refresh.mutate(),
            disabled: refresh.isPending,
          },
        ]}
      />

      <StatRibbon borderTop={false} stats={([
        ...(position ? [
          { label: "Market Value",   value: formatCurrency(position.market_value, true) },
          { label: "Cost Basis",     value: formatCurrency(position.cost_basis, true) },
          { label: "Unrealized G/L", value: formatCurrency(position.unrealized_gl, true), highlight: glPositive ? "positive" : "negative" },
          { label: "Shares",         value: position.quantity.toLocaleString() },
        ] : []),
        ...(dividends.last_12mo > 0 ? [{ label: "Dividends (12mo)", value: formatCurrency(dividends.last_12mo), dividerBefore: position != null }] : []),
        ...(dividends.ytd > 0 ? [{ label: "Dividends YTD", value: formatCurrency(dividends.ytd) }] : []),
      ] as StatItem[])} />

      <div className="p-6">
        <div className="grid gap-6 lg:grid-cols-[1fr_280px]">
          {/* Left column: price header + chart + transaction history */}
          <div className="space-y-6">
            <div>
              <div className="mb-4">
                <p className="text-sm text-muted-foreground">
                  {data.name}
                  {data.ticker && <span className="ml-2 font-mono text-xs">{data.ticker}</span>}
                </p>
                <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1">
                  {latestClose != null && (
                    <span className="text-3xl font-bold tabular-nums tracking-tight">
                      {formatCurrency(latestClose)}
                    </span>
                  )}
                  {rangePctChange != null && rangeAbsChange != null && (
                    <div className={cn("flex items-center gap-1.5 font-semibold", moneyColor(rangeAbsChange))}>
                      <span className={cn("flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-white", rangePositive ? "bg-positive" : "bg-negative")}>
                        {rangePositive ? <ArrowUp size={11} strokeWidth={2.5} /> : <ArrowDown size={11} strokeWidth={2.5} />}
                      </span>
                      <span className="text-base">
                        {rangePositive ? "+" : ""}{rangePctChange.toFixed(2)}%
                        {" "}({rangePositive ? "+" : ""}{formatCurrency(rangeAbsChange)})
                        {" "}{rangeLabel}
                      </span>
                    </div>
                  )}
                </div>
                <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
                  {latest_price && (
                    <>
                      <span>
                        As of {formatDate(latest_price.date)} · USD
                        {latest_price.source ? ` · ${priceSourceLabel(latest_price.source)}` : ""}
                      </span>
                      <StalenessBadge price={latest_price} />
                    </>
                  )}
                  {/* Crypto isn't watchable through this endpoint — those rows
                      are priced from CoinGecko/CMC, not the watch sync. */}
                  {data.ticker && data.security_type !== "Crypto" && (
                    <>
                      {latest_price && <span className="select-none text-border">·</span>}
                      <button
                        type="button"
                        className="font-medium text-primary hover:underline disabled:opacity-50"
                        disabled={watch.isPending || unwatch.isPending}
                        onClick={() => data.watched
                          ? unwatch.mutate(data.ticker)
                          : watch.mutate({ ticker: data.ticker, name: data.name, instrument_class: data.instrument_class })}
                      >
                        {data.watched ? "Remove from watchlist" : "Add to watchlist"}
                      </button>
                    </>
                  )}
                </div>
              </div>
              <AdvancedPriceChart
                data={candleData}
                isLoading={candlesLoading}
                range={range}
                onRangeChange={setRange}
                comparisons={comparisonSeries}
                toolbarExtra={
                  <BenchmarkCombobox
                    selected={comparisons}
                    onAdd={(sym) => setComparisons((prev) => prev.includes(sym) ? prev : [...prev, sym])}
                    onRemove={(sym) => setComparisons((prev) => prev.filter((s) => s !== sym))}
                    suggestions={(benchmarkMeta ?? []).filter((b) => b.symbol !== data.ticker)}
                    colors={comparisonColors}
                  />
                }
              />
            </div>

            <div>
              <Tabs
                className="mb-3"
                value={activeTab}
                onChange={setActiveTab}
                options={[
                  { value: "transactions", label: "Transactions" },
                  { value: "lots", label: "Lots", count: lots.length > 0 ? lots.length : undefined },
                  { value: "news", label: "News" },
                ]}
              />

              {activeTab === "transactions" && (
                <Card>
                  <CardContent className="p-0">
                    <InvestmentTransactionTable
                      transactions={recent_transactions}
                      showSecurity={false}
                      onReprocessed={() => invalidate(qc, queries.security(id).queryKey)}
                    />
                  </CardContent>
                </Card>
              )}

              {activeTab === "lots" && (
                <Card>
                  <CardContent className="p-0">
                    <InvestmentLotsEditor
                      securityId={securityUuid}
                      lots={lots}
                      accounts={accounts}
                      onChanged={() => {
                        refetchLots();
                        invalidate(qc, keys.costBasis, queries.security(id).queryKey, keys.portfolio);
                      }}
                    />
                  </CardContent>
                </Card>
              )}

              {activeTab === "news" && (
                <NewsPanel articles={newsData ?? []} isLoading={newsLoading} />
              )}
            </div>
          </div>

          {/* Right column: holdings + overview + dividends */}
          <div className="space-y-6">
            {position && position.by_account.length > 0 && (
              <div>
                <ChartLabel>Holdings by Account</ChartLabel>
                <KeyValueTable
                  mutedLabels
                  rows={position.by_account.map((row) => ({
                    key: row.account,
                    label: row.account,
                    value: formatCurrency(row.market_value),
                  }))}
                />
              </div>
            )}
            {dividends.lifetime > 0 && (
              <div>
                <ChartLabel>Dividend Income</ChartLabel>
                <Card>
                  <CardContent className="p-0">
                    <table className="w-full text-sm">
                      <tbody className="divide-y">
                        <tr>
                          <td className="px-4 py-2.5 text-muted-foreground">YTD</td>
                          <td className="px-4 py-2.5 text-right tabular-nums">{formatCurrency(dividends.ytd)}</td>
                        </tr>
                        <tr>
                          <td className="px-4 py-2.5 text-muted-foreground">Last 12 months</td>
                          <td className="px-4 py-2.5 text-right tabular-nums">{formatCurrency(dividends.last_12mo)}</td>
                        </tr>
                        <tr>
                          <td className="px-4 py-2.5 text-muted-foreground">Lifetime</td>
                          <td className="px-4 py-2.5 text-right tabular-nums">{formatCurrency(dividends.lifetime)}</td>
                        </tr>
                      </tbody>
                    </table>
                  </CardContent>
                </Card>
              </div>
            )}
            {overview && <OverviewCard overview={overview} currentPrice={latestClose} />}
            <ExternalLinksCard ticker={data.ticker} exchange={overview?.exchange ?? null} securityType={data.security_type} slug={data.slug} />
            <SecurityConversionsCard securityId={data.id} />
          </div>
        </div>
      </div>

      {addingTx && (
        <AddInvestmentTransactionDrawer
          securityId={data.id}
          securityTicker={data.ticker}
          onClose={() => setAddingTx(false)}
          onCreated={() => setAddingTx(false)}
        />
      )}
    </div>
  );
}

function OverviewRow({ label, value }: { label: string; value: React.ReactNode }) {
  if (value == null || value === "—") return null;
  return (
    <tr>
      <td className="px-4 py-2.5 text-muted-foreground">{label}</td>
      <td className="px-4 py-2.5 text-right tabular-nums">{value}</td>
    </tr>
  );
}

function OverviewCard({ overview, currentPrice }: { overview: SecurityOverview; currentPrice: number | null }) {
  const fmtPct = (n: number | null) => n != null ? `${(n * 100).toFixed(2)}%` : null;
  const fmtNum = (n: number | null, dp = 2) => n != null ? n.toFixed(dp) : null;

  const range52w = overview.week_52_low != null && overview.week_52_high != null
    ? `${formatCurrency(overview.week_52_low)} – ${formatCurrency(overview.week_52_high)}`
    : null;

  return (
    <div>
      <ChartLabel>Company Overview</ChartLabel>
      {overview.description && (
        <p className="mb-3 text-xs text-muted-foreground leading-relaxed line-clamp-4">{overview.description}</p>
      )}
      <Card>
        <CardContent className="p-0">
          <table className="w-full text-sm">
            <tbody className="divide-y">
              <OverviewRow label="Market Cap"     value={formatCurrency(overview.market_cap, true)} />
              <OverviewRow label="Revenue (TTM)"  value={formatCurrency(overview.revenue_ttm, true)} />
              <OverviewRow label="P/E Ratio"      value={fmtNum(overview.pe_ratio)} />
              <OverviewRow label="Forward P/E"    value={fmtNum(overview.forward_pe)} />
              <OverviewRow label="EPS"            value={overview.eps != null ? formatCurrency(overview.eps) : null} />
              <OverviewRow label="Beta"           value={fmtNum(overview.beta)} />
              <OverviewRow label="52-Week Range"  value={range52w} />
              <OverviewRow label="Div. Yield"     value={fmtPct(overview.dividend_yield)} />
              <OverviewRow label="Analyst Target" value={overview.analyst_target_price != null ? formatCurrency(overview.analyst_target_price) : null} />
              <OverviewRow label="Profit Margin"  value={fmtPct(overview.profit_margin)} />
              <OverviewRow label="ROE"            value={fmtPct(overview.return_on_equity)} />
              <OverviewRow
                label="Shares Out."
                value={overview.shares_outstanding != null
                  ? formatCompactNumber(overview.shares_outstanding, 2)
                  : null}
              />
            </tbody>
          </table>
        </CardContent>
      </Card>
      <Range52Bar low={overview.week_52_low} high={overview.week_52_high} current={currentPrice} />
      {(overview.sector || overview.industry) && (
        <p className="mt-2 text-xs text-muted-foreground">
          {[overview.sector, overview.industry].filter(Boolean).join(" · ")}
        </p>
      )}
    </div>
  );
}

/** Where today's price sits inside the 52-week range. */
function Range52Bar({ low, high, current }: { low: number | null; high: number | null; current: number | null }) {
  if (low == null || high == null || current == null || high <= low) return null;
  const position = Math.min(100, Math.max(0, ((current - low) / (high - low)) * 100));

  return (
    <div className="mt-2 px-1">
      <div className="relative h-1 rounded-full bg-muted">
        <div
          className="absolute -top-0.5 h-2 w-2 -translate-x-1/2 rounded-full bg-primary ring-2 ring-card"
          style={{ left: `${position}%` }}
          title={`${formatCurrency(current)} — ${position.toFixed(0)}% of the 52-week range`}
        />
      </div>
      <div className="mt-1 flex justify-between text-tiny tabular-nums text-muted-foreground">
        <span>{formatCurrency(low)}</span>
        <span>52-wk</span>
        <span>{formatCurrency(high)}</span>
      </div>
    </div>
  );
}

function NewsPanel({ articles, isLoading }: { articles: NewsArticle[]; isLoading: boolean }) {
  if (isLoading) {
    return (
      <div className="space-y-3">
        {[1, 2, 3, 4].map(i => (
          <div key={i} className="rounded-xl border p-4 space-y-2">
            <Skeleton className="h-4 w-3/4" />
            <Skeleton className="h-3 w-full" />
            <Skeleton className="h-3 w-2/3" />
          </div>
        ))}
      </div>
    );
  }

  if (articles.length === 0) {
    return <EmptyState title="No recent news found." />;
  }

  const sentimentColor = (s: string | null) => {
    if (!s) return "text-muted-foreground";
    if (s.toLowerCase().includes("bullish")) return "text-positive";
    if (s.toLowerCase().includes("bearish")) return "text-negative";
    return "text-muted-foreground";
  };

  return (
    <div className="divide-y">
      {articles.map((a, i) => (
        <div key={i} className="py-2.5">
          <a
            href={a.url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm font-medium hover:underline"
          >
            {a.title}
          </a>
          {a.summary && (
            <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{a.summary}</p>
          )}
          <div className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
            <span>{a.source}</span>
            {a.published_at && (
              <span>· {new Date(
                a.published_at.replace(/(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/, '$1-$2-$3T$4:$5:$6')
              ).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}</span>
            )}
            {a.sentiment && (
              <span className={cn("font-medium capitalize", sentimentColor(a.sentiment))}>
                · {a.sentiment.replace(/_/g, " ").toLowerCase()}
              </span>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

function ExternalLinksCard({ ticker, exchange, securityType, slug }: { ticker: string; exchange: string | null; securityType: string | null; slug: string | null }) {
  const isCrypto = securityType === "Crypto";
  const coinSlug = slug ?? ticker.toLowerCase();
  const links = isCrypto
    ? [
        { label: "CoinMarketCap", href: `https://coinmarketcap.com/currencies/${coinSlug}/` },
        { label: "CoinGecko",     href: `https://www.coingecko.com/en/coins/${coinSlug}` },
        { label: "Coinbase",      href: `https://www.coinbase.com/price/${coinSlug}` },
      ]
    : [
        {
          label: "Google Finance",
          href: exchange
            ? `https://www.google.com/finance/quote/${ticker}:${exchange}`
            : `https://www.google.com/finance/quote/${ticker}`,
        },
        {
          label: "Yahoo Finance",
          href: `https://finance.yahoo.com/quote/${ticker}/`,
        },
        {
          label: "TradingView",
          href: exchange
            ? `https://www.tradingview.com/symbols/${exchange}-${ticker}/`
            : `https://www.tradingview.com/symbols/${ticker}/`,
        },
      ];

  return (
    <div>
      <ChartLabel>View On</ChartLabel>
      <Card>
        <CardContent className="p-0">
          <ul className="divide-y text-sm">
            {links.map(({ label, href }) => (
              <li key={label}>
                <a
                  href={href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center justify-between px-4 py-2.5 text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
                >
                  {label}
                  <ExternalLink size={12} className="shrink-0 opacity-50" />
                </a>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </div>
  );
}

function LoadingState() {
  return (
    <div className="flex flex-col">
      <div className="flex h-14 items-center border-b px-6"><Skeleton className="h-5 w-32" /></div>
      <div className="h-12 border-b bg-muted/40 animate-pulse" />
      <div className="space-y-6 p-6">
        <Skeleton className="h-48 rounded-xl" />
        <div className="grid gap-6 lg:grid-cols-[1fr_260px]">
          <Skeleton className="h-64 rounded-xl" />
          <div className="space-y-4">
            <Skeleton className="h-32 rounded-xl" />
            <Skeleton className="h-24 rounded-xl" />
          </div>
        </div>
      </div>
    </div>
  );
}
