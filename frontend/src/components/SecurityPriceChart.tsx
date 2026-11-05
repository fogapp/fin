import React, { useMemo } from "react";
import { LineChart } from "@/components/charts";
import { Tabs } from "@/components/ui/tabs";
import { formatCurrency } from "@/lib/utils";
import { PERIODS, cutoffFor, type Period, type PriceData } from "@/lib/pricePeriods";

export type { Period, PriceData };

const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

function formatXTick(dateStr: string, period: Period): string {
  const [year, mm, dd] = dateStr.split("-");
  const month = MONTHS[parseInt(mm) - 1];
  if (period === "1M") return `${month} ${parseInt(dd)}`;
  if (period === "5Y" || period === "MAX") return year;
  return month;
}

function defaultYFormatter(v: number): string {
  return v >= 1000 ? `${(v / 1000).toFixed(0)}k` : `${v.toFixed(0)}`;
}

interface Props {
  data: PriceData;
  period: Period;
  onPeriodChange: (p: Period) => void;
  /** Override Y-axis tick labels. Default: plain number (e.g. "25k"). */
  yFormatter?: (v: number) => string;
  /** Override tooltip value display. Default: formatCurrency. */
  valueFormatter?: (v: number) => string;
  /** Content rendered to the left of the period tabs (e.g. a comparison combobox). */
  toolbarLeft?: React.ReactNode;
}

export function SecurityPriceChart({
  data, period, onPeriodChange,
  yFormatter = defaultYFormatter,
  valueFormatter = formatCurrency,
  toolbarLeft,
}: Props) {
  const chartData = useMemo(() => {
    const cutoff = cutoffFor(period);
    const filtered = cutoff ? data.filter(([d]) => d >= cutoff) : data;
    return filtered.map((entry) => ({ date: entry[0], close: entry[1] }));
  }, [data, period]);

  const firstClose = chartData[0]?.close ?? null;

  return (
    <div>
      <LineChart
        data={chartData}
        series={[{ key: "close", label: "Price" }]}
        xKey="date"
        height={230}
        area
        yFormat={yFormatter}
        valueFormat={valueFormatter}
        xTickFormat={(v) => formatXTick(v, period)}
        referenceY={firstClose ?? undefined}
        referenceYLabel={firstClose != null ? valueFormatter(firstClose) : undefined}
      />

      <div className="mt-2 flex items-center justify-between gap-2">
        <div>{toolbarLeft}</div>
        <Tabs
          size="sm"
          value={period}
          onChange={onPeriodChange}
          options={PERIODS.map((p) => ({ value: p, label: p }))}
        />
      </div>
    </div>
  );
}
