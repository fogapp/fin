/**
 * The Market page's home pane: benchmark indices strip, a portfolio pulse
 * row, biggest movers among tracked instruments, and an aggregated news
 * feed — the Google Finance-style overview, scoped to the household's
 * tracked universe.
 */
import { useQuery } from "@tanstack/react-query";
import { ArrowUpRight, ArrowDownRight, Newspaper } from "lucide-react";
import { queries } from "@/api/queries";
import { PageHeader } from "@/components/layout/PageHeader";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { ChartLabel } from "@/components/charts";
import { TrendSparkline } from "./TrendSparkline";
import { ChangePct } from "./ChangePct";
import { cn, formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import type { MoverStat, MarketNewsItem } from "@/api/types";

interface Props {
  onSelect: (param: string) => void;
}

export function MarketOverview({ onSelect }: Props) {
  const { data: summary, isLoading, isError, refetch } = useQuery(queries.marketSummary());
  const { data: portfolio } = useQuery(queries.portfolio());
  const { data: performance } = useQuery(queries.portfolioPerformance());

  if (isLoading) return <OverviewSkeleton />;
  if (isError || !summary) {
    return (
      <div className="flex flex-col">
        <PageHeader title="Market" level={1} />
        <ErrorState title="Failed to load market overview" onRetry={() => refetch()} />
      </div>
    );
  }

  const indices = (summary.indices ?? []).filter((i) => i.close != null);
  const news = summary.news ?? [];
  const gainers = summary.movers?.gainers ?? [];
  const losers = summary.movers?.losers ?? [];
  const hasMovers = gainers.length > 0 || losers.length > 0;

  const portfolioSummary = portfolio?.summary;
  const history = portfolio?.portfolio_history
    ? Object.entries(portfolio.portfolio_history).sort(([a], [b]) => a.localeCompare(b)).map(([, v]) => v)
    : [];

  return (
    <div className="flex flex-col">
      <PageHeader title="Market" level={1} subtitle={summary.as_of ? `as of ${formatDate(summary.as_of)}` : undefined} />

      <div className="space-y-6 p-6">
        {/* Indices strip */}
        {indices.length > 0 && (
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            {indices.map((index) => (
              <Card key={index.symbol}>
                <CardContent className="flex items-center justify-between gap-2 p-3">
                  <div className="min-w-0">
                    <p className="truncate text-xs font-medium text-muted-foreground">{index.label}</p>
                    <p className="text-sm font-semibold tabular-nums">{formatCurrency(index.close!)}</p>
                    <ChangePct value={index.day_change_pct} className="text-xs font-medium" />
                  </div>
                  <TrendSparkline data={index.spark} className="shrink-0" />
                </CardContent>
              </Card>
            ))}
          </div>
        )}

        {/* Portfolio pulse */}
        {portfolioSummary && portfolioSummary.total_value > 0 && (
          <div>
            <ChartLabel>Your Portfolio</ChartLabel>
            <Card>
              <CardContent className="flex flex-wrap items-center gap-x-8 gap-y-3 p-4">
                <div>
                  <p className="text-xs text-muted-foreground">Total value</p>
                  <p className="text-xl font-bold tabular-nums tracking-tight">
                    {formatCurrency(portfolioSummary.total_value, true)}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">Unrealized G/L</p>
                  <p className={cn("text-sm font-semibold tabular-nums",
                    moneyColor(portfolioSummary.unrealized_gl))}>
                    {portfolioSummary.unrealized_gl >= 0 ? "+" : ""}{formatCurrency(portfolioSummary.unrealized_gl, true)}
                  </p>
                </div>
                {performance?.twr_pct != null && (
                  <div title="Time-weighted return: performance of the picks themselves, comparable to a benchmark.">
                    <p className="text-xs text-muted-foreground">TWR (1Y)</p>
                    <p className="text-sm font-semibold"><ChangePct value={performance.twr_pct} /></p>
                  </div>
                )}
                {performance?.xirr_pct != null && (
                  <div title="Money-weighted return (XIRR): what your invested dollars actually earned, including timing.">
                    <p className="text-xs text-muted-foreground">XIRR (1Y)</p>
                    <p className="text-sm font-semibold"><ChangePct value={performance.xirr_pct} /></p>
                  </div>
                )}
                {history.length > 1 && (
                  <TrendSparkline data={history} width={120} height={32} className="ml-auto" />
                )}
              </CardContent>
            </Card>
          </div>
        )}

        {/* Movers */}
        {hasMovers && (
          <div className="grid gap-6 md:grid-cols-2">
            <MoversList title="Top Gainers" icon={ArrowUpRight} movers={gainers} onSelect={onSelect} />
            <MoversList title="Top Losers" icon={ArrowDownRight} movers={losers} onSelect={onSelect} />
          </div>
        )}

        {/* News feed */}
        <div>
          <ChartLabel>News</ChartLabel>
          {news.length === 0 ? (
            <EmptyState
              icon={Newspaper}
              title="No news yet"
              description="News syncs for tracked equities as providers publish it."
              className="py-10"
            />
          ) : (
            <div className="divide-y">
              {news.map((article) => (
                <NewsRow key={article.url} article={article} onSelect={onSelect} />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function MoversList({ title, icon: Icon, movers, onSelect }: {
  title: string;
  icon: React.ComponentType<{ size?: number | string; className?: string }>;
  movers: MoverStat[];
  onSelect: (param: string) => void;
}) {
  return (
    <div>
      <ChartLabel>{title}</ChartLabel>
      {movers.length === 0 ? (
        <p className="py-4 text-xs text-muted-foreground">Nothing moving today.</p>
      ) : (
        <Card>
          <CardContent className="divide-y p-0">
            {movers.map((mover) => (
              <button
                key={mover.id}
                onClick={() => onSelect(mover.param)}
                className="flex w-full items-center gap-3 px-4 py-2.5 text-left text-sm transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
              >
                <Icon size={14} className={cn("shrink-0", moneyColor(mover.day_change_pct))} />
                <div className="min-w-0 flex-1">
                  <p className="font-medium leading-tight">{mover.ticker ?? mover.display_name}</p>
                  <p className="truncate text-caption leading-tight text-muted-foreground">{mover.name}</p>
                </div>
                <TrendSparkline data={mover.spark} className="shrink-0" />
                <div className="w-20 text-right">
                  {mover.close != null && <p className="text-xs tabular-nums leading-tight">{formatCurrency(mover.close)}</p>}
                  <ChangePct value={mover.day_change_pct} className="text-xs font-medium" />
                </div>
              </button>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function NewsRow({ article, onSelect }: { article: MarketNewsItem; onSelect: (param: string) => void }) {
  const sentimentColor = article.sentiment?.toLowerCase().includes("bullish")
    ? "text-positive"
    : article.sentiment?.toLowerCase().includes("bearish")
      ? "text-negative"
      : "text-muted-foreground";

  return (
    <div className="py-2.5">
      <div className="flex items-start gap-2">
        {article.ticker && article.param && (
          <button
            onClick={() => onSelect(article.param!)}
            className="mt-px shrink-0 rounded-full bg-muted px-1.5 py-px text-tiny font-semibold text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            {article.ticker}
          </button>
        )}
        <a
          href={article.url}
          target="_blank"
          rel="noopener noreferrer"
          className="min-w-0 text-sm font-medium leading-snug hover:underline"
        >
          {article.title}
        </a>
      </div>
      {article.summary && <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{article.summary}</p>}
      <div className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
        <span>{article.source}</span>
        {article.published_at && <span>· {formatNewsDate(article.published_at)}</span>}
        {article.sentiment && (
          <span className={cn("font-medium capitalize", sentimentColor)}>
            · {article.sentiment.replace(/_/g, " ").toLowerCase()}
          </span>
        )}
      </div>
    </div>
  );
}

/** AlphaVantage timestamps arrive as YYYYMMDDTHHMMSS. */
function formatNewsDate(raw: string): string {
  const iso = raw.replace(/(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/, "$1-$2-$3T$4:$5:$6");
  const date = new Date(iso);
  return Number.isNaN(date.getTime())
    ? raw
    : date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function OverviewSkeleton() {
  return (
    <div className="flex flex-col">
      <div className="flex h-14 items-center border-b px-6"><Skeleton className="h-5 w-24" /></div>
      <div className="space-y-6 p-6">
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-16 rounded-xl" />)}
        </div>
        <Skeleton className="h-20 rounded-xl" />
        <div className="grid gap-6 md:grid-cols-2">
          <Skeleton className="h-48 rounded-xl" />
          <Skeleton className="h-48 rounded-xl" />
        </div>
      </div>
    </div>
  );
}
