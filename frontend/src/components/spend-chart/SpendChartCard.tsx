/**
 * The reusable spend-over-time card: a monthly spend series with a
 * Total / by-Category / by-Merchant split, an $ / % scale, and an
 * outlier-aware Common/Outlier/Both series mode — for every page that shows
 * segmented spend time series (Cashflow > Spending, category and tag details).
 *
 * Data comes from GET /cashflow/spend_breakdown scoped by account/tag/
 * category/merchant, which also carries the Total line's series — so a bare
 * `<SpendChartCard scope timeframe controls />` is self-sufficient. A page
 * that already holds the total series (Cashflow > Spending's index payload)
 * passes them via `totals`, and the breakdown is then only fetched once a
 * split is actually selected.
 *
 * `variant="compact"` strips all of that down to the Total bars alone — no
 * card chrome, no toggles — for detail pages (account, merchant, category
 * context) whose sections carry their own headers but should still draw the
 * same spend numbers from the same endpoint.
 *
 * Control placement is the page's call: the split + scale toggles always live
 * in the card header (they only affect this chart); the series mode and
 * timeframe controls render there too when `showSeriesToggle` /
 * `showTimeframeSelector` are set, for pages without a page-level header that
 * scopes more than the chart.
 */
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  AreaChart, BarChart, ChartCard, LineChart, SegmentedToggle, TimeframeSelector,
  transactionsHref, useChartTheme, assignSeriesColors,
  type Timeframe, type SeriesDef, type ChartDatum,
} from "@/components/charts";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { queries } from "@/api/queries";
import { fillMonthsFrom } from "@/lib/utils";
import { buildSpendBands, bandNames, OTHER_ID, type SpendScale } from "./spendBands";
import { SPEND_SERIES_OPTIONS, type SpendChartControls, type SpendDimension } from "./useSpendChartControls";
import type { SpendBreakdown, SpendBreakdownData } from "@/api/types";

const DIMENSION_OPTIONS: { value: SpendDimension; label: string }[] = [
  { value: "none",     label: "Total" },
  { value: "category", label: "Category" },
  { value: "merchant", label: "Merchant" },
];

const SCALE_OPTIONS: { value: SpendScale; label: string }[] = [
  { value: "amount", label: "$" },
  { value: "share",  label: "%" },
];

/** What the chart's numbers are scoped to. Doubles as the default drill
 *  target: clicking a month lands on /transactions filtered the same way. */
export interface SpendChartScope {
  accountId?: string;
  tagId?: string;
  excludeTagIds?: string[];
  categoryId?: string;
  merchantId?: string;
}

// The compact variant has no mode toggles — it always shows actual spend
// ("outlier") as a single Total series.
const COMPACT_CONTROLS: SpendChartControls = {
  seriesMode: "outlier", setSeriesMode: () => {},
  dimension: "none", setDimension: () => {},
  scale: "amount", setScale: () => {},
};

/** First day of the month `n` months before the current one, as an ISO date. */
function firstOfMonthsAgo(n: number): string {
  const today = new Date();
  const d = new Date(today.getFullYear(), today.getMonth() - n, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01`;
}

/** The Total line's month → amount maps, when the page already has them. */
export interface SpendTotals {
  spend: Record<string, number>;
  common: Record<string, number>;
}

export function SpendChartCard({
  title = "Monthly Spend",
  scope = {},
  variant = "default",
  height = 160,
  highlightX,
  timeframe,
  controls,
  showSeriesToggle = false,
  showTimeframeSelector = false,
  totals,
  colors,
  linkFor,
  onSelectMonth,
  className,
}: {
  title?: string;
  scope?: SpendChartScope;
  /** "compact": just the Total bars, no card chrome and no mode/scale
   *  controls — for detail-page sections that already carry their own
   *  header. `controls` is ignored, and `timeframe` may be omitted (the
   *  window then defaults to the last 24 months). */
  variant?: "default" | "compact";
  /** Compact only: the bar chart's height. */
  height?: number;
  /** Compact only: de-emphasize every month except this one ("yyyy-mm"). */
  highlightX?: string;
  timeframe?: Timeframe;
  controls?: SpendChartControls;
  /** Render the Common/Outlier/Both toggle in the card header (for pages
   *  where it doesn't already live in a page-level header). */
  showSeriesToggle?: boolean;
  /** Same, for the timeframe control. */
  showTimeframeSelector?: boolean;
  /** Preloaded Total-line series; when given, the breakdown endpoint is only
   *  hit once a split is selected. */
  totals?: SpendTotals;
  /** Shared entity→color maps (a page whose other panels must agree with the
   *  bands, like Spending's ranked lists). Defaults to a chart-local
   *  assignment from the breakdown's own band names. */
  colors?: { category: Map<string, string>; merchant: Map<string, string> };
  /** Month drill override; default links to /transactions scoped like the
   *  chart. */
  linkFor?: (month: string) => string;
  /** In-page month drill (e.g. filter a table below) instead of navigating. */
  onSelectMonth?: (month: string) => void;
  className?: string;
}) {
  const theme = useChartTheme();
  const compact = variant === "compact";
  const { seriesMode, setSeriesMode, dimension, setDimension, scale, setScale } =
    compact || !controls ? COMPACT_CONTROLS : controls;
  const showCommon = seriesMode === "common";

  // Compact call sites have no timeframe UI; default their window to the last
  // 24 months — the span the hand-rolled fillLastMonths charts used to show.
  const from = timeframe?.from ?? (compact ? firstOfMonthsAgo(23) : undefined);
  const to = timeframe?.to;

  // The month × entity grid behind the stacked modes — and, for pages with no
  // cashflow payload of their own, the Total line too.
  const breakdownQuery = useQuery({
    ...queries.cashflowSpendBreakdown({
      from, to,
      account_id: scope.accountId, tag_id: scope.tagId, exclude_tag_ids: scope.excludeTagIds,
      category_id: scope.categoryId,
      merchant_id: scope.merchantId,
    }),
    enabled: dimension !== "none" || !totals,
  });
  const breakdown = dimension === "none" ? null : pickBreakdown(breakdownQuery.data, dimension, showCommon);

  const totalSeries = useMemo(
    () => totals
      ?? (breakdownQuery.data?.monthly_spend && {
        spend: breakdownQuery.data.monthly_spend,
        common: breakdownQuery.data.monthly_spend_common ?? breakdownQuery.data.monthly_spend,
      }),
    [totals, breakdownQuery.data],
  );

  // "Outlier" = total spend as it actually happened; "Common" = the same
  // series with flagged-outlier amounts subtracted — merged by month key
  // rather than zipped by index so a gap in either series can't misalign them.
  const monthlyData = useMemo(() => {
    if (!totalSeries) return [];
    const outlierByMonth = fillMonthsFrom(totalSeries.spend, from);
    const commonByMonth = new Map(fillMonthsFrom(totalSeries.common, from).map((d) => [d.month, d.amount]));
    return outlierByMonth.map((d) => ({ month: d.month, outlier: d.amount, common: commonByMonth.get(d.month) ?? d.amount }));
  }, [totalSeries, from]);

  const chartSeries: SeriesDef[] = useMemo(() => {
    if (seriesMode === "common") return [{ key: "common", label: "Common" }];
    if (seriesMode === "outlier") return [{ key: "outlier", label: "Outlier" }];
    return [{ key: "outlier", label: "Outlier" }, { key: "common", label: "Common" }];
  }, [seriesMode]);

  // Chart-local color assignment from the breakdown's own band names (both
  // variants, so toggling Common can't recolor a band), unless the page
  // supplies a shared map for the active dimension.
  const sharedColors = dimension === "merchant" ? colors?.merchant : colors?.category;
  const activeColors = useMemo(() => {
    if (sharedColors) return sharedColors;
    if (dimension === "none") return new Map<string, string>();
    return assignSeriesColors(bandNames(breakdownQuery.data, dimension).map((band) => band.name), theme);
  }, [sharedColors, dimension, breakdownQuery.data, theme]);

  // Bands and rows are built together — folding an unslotted band into Other
  // has to move its values, not just its label — over monthlyData's month
  // axis, so switching modes never shifts the x-axis.
  const { series: breakdownSeries, rows: breakdownData } = useMemo(
    () => breakdown
      ? buildSpendBands(
          breakdown,
          monthlyData.map((d) => d.month),
          activeColors,
          theme.neutral,
          scale,
        )
      : { series: [], rows: [] },
    [breakdown, activeColors, monthlyData, scale, theme],
  );

  const drill = onSelectMonth
    ? { onSelect: (d: ChartDatum) => onSelectMonth(String(d.x)) }
    : {
        linkFor: (d: ChartDatum) => linkFor
          ? linkFor(String(d.x))
          : transactionsHref({
              month: String(d.x),
              accountId: scope.accountId, tagId: scope.tagId, excludeTagIds: scope.excludeTagIds,
              categoryId: scope.categoryId,
              merchantId: scope.merchantId,
            }),
      };

  if (compact) {
    if (breakdownQuery.error) {
      return <ErrorState title="Failed to load spending" onRetry={() => breakdownQuery.refetch()} />;
    }
    if (!totalSeries) return <Skeleton className="rounded-lg" style={{ height }} />;
    return (
      <BarChart
        data={monthlyData.map((d) => ({ month: d.month, spend: d.outlier }))}
        series={[{ key: "spend", label: "Spend" }]}
        height={height}
        highlightX={highlightX}
        {...drill}
      />
    );
  }

  return (
    <ChartCard
      title={title}
      subtitle={breakdownSubtitle(dimension, scale, showCommon)}
      className={className}
      control={(
        <div className="flex flex-wrap items-center justify-end gap-1.5">
          {showSeriesToggle && (
            <SegmentedToggle label="Spend series" options={SPEND_SERIES_OPTIONS} value={seriesMode} onChange={setSeriesMode} />
          )}
          <SegmentedToggle label="Spend split" options={DIMENSION_OPTIONS} value={dimension} onChange={setDimension} />
          {dimension !== "none" && (
            <SegmentedToggle label="Spend scale" options={SCALE_OPTIONS} value={scale} onChange={setScale} />
          )}
          {showTimeframeSelector && timeframe && (
            <TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />
          )}
        </div>
      )}
    >
      {/* isPending, not isLoading: the frame right after `enabled` flips has
          nothing fetching yet, and would flash the empty state. */}
      {dimension === "none" ? (
        !totalSeries ? (
          breakdownQuery.error
            ? <ErrorState title="Failed to load spending" onRetry={() => breakdownQuery.refetch()} />
            : <Skeleton className="h-[200px] rounded-lg" />
        ) : (
          <LineChart
            data={monthlyData}
            series={chartSeries}
            height={200}
            area
            {...drill}
          />
        )
      ) : breakdownQuery.isPending ? (
        <Skeleton className="h-[240px] rounded-lg" />
      ) : breakdownQuery.error ? (
        <ErrorState title="Failed to load the spend breakdown" onRetry={() => breakdownQuery.refetch()} />
      ) : breakdownSeries.every((band) => band.key === OTHER_ID) ? (
        // All-Other is not a split — it's the total line painted gray.
        <EmptyState
          title={dimension === "category" ? "No categorized spending" : "No merchant spending"}
          description="Nothing to split up in this timeframe."
          className="py-16"
        />
      ) : scale === "share" ? (
        <AreaChart
          data={breakdownData}
          series={breakdownSeries}
          height={240}
          percent
          {...drill}
        />
      ) : (
        <BarChart
          data={breakdownData}
          series={breakdownSeries}
          height={240}
          stacked
          {...drill}
        />
      )}
    </ChartCard>
  );
}

function pickBreakdown(
  data: SpendBreakdownData | undefined,
  dimension: "category" | "merchant",
  common: boolean,
): SpendBreakdown | null {
  if (!data) return null;
  return (common ? data[`${dimension}_common`] : data[dimension]) ?? null;
}

/** What the chart is showing, spelled out — the bands are a top-N with a
 *  catch-all, which the reader can't infer from the marks alone. */
function breakdownSubtitle(dimension: SpendDimension, scale: SpendScale, showCommon: boolean): string | undefined {
  if (dimension === "none") return undefined;
  const by = dimension === "category" ? "category" : "merchant";
  const what = scale === "share" ? `Share of each month's spend by ${by}` : `Each month's spend by ${by}`;
  return `${what} · top 8, everything else in Other${showCommon ? " · excl. outliers" : ""}`;
}
