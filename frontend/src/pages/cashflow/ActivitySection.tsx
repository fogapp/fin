import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { queries } from "@/api/queries";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { StatRibbon } from "@/components/StatRibbon";
import { Skeleton } from "@/components/ui/skeleton";
import { ChartLabel, LineChart, BarChart } from "@/components/charts";
import { cn, formatCurrency, moneyColor } from "@/lib/utils";

const TXN_FILTER_KEY = "txn_filters:/transactions";

export function ActivitySection() {
  const navigate = useNavigate();
  const { data, isLoading, refetch } = useQuery(queries.cashflowActivity());

  if (isLoading) return (
    <div className="flex flex-col">
      <div className="h-14 border-b" />
      <Skeleton className="h-12 rounded-none border-b bg-muted/40" />
      <div className="space-y-6 p-6">
        <Skeleton className="h-48 rounded-xl" />
        <Skeleton className="h-64 rounded-xl" />
      </div>
    </div>
  );
  if (!data) return <ErrorState title="Failed to load activity" onRetry={() => refetch()} />;

  const { days, total_spend, total_income, net } = data;
  const netPositive = net >= 0;

  function goToDate(date: string) {
    const filter = [{ _key: 1, field: "transaction_date", operator: "equals", value: date }];
    sessionStorage.setItem(TXN_FILTER_KEY, JSON.stringify(filter));
    navigate("/transactions");
  }

  const chartData = days.map((d) => ({
    date: d.date,
    spend: d.spend,
    income: d.income,
    net: +(d.income - d.spend).toFixed(2),
  }));

  return (
    <div className="flex flex-col">
      <PageHeader title="Activity" subtitle="past 30 days" />

      <StatRibbon borderTop={false} stats={[
        { label: "Spend",  value: formatCurrency(total_spend, true) },
        { label: "Income", value: formatCurrency(total_income, true) },
        { label: "Net",    value: formatCurrency(net, true), highlight: netPositive ? "positive" : "negative" },
      ]} />

      <div className="space-y-8 p-6">
        <div>
          <ChartLabel>Daily Spend &amp; Income</ChartLabel>
          <LineChart
            data={chartData}
            series={[{ key: "spend", label: "Spend" }, { key: "income", label: "Income" }]}
            xKey="date"
            height={220}
            dots
            onSelect={(d) => goToDate(d.x)}
          />
        </div>

        <div>
          <ChartLabel>Daily Net</ChartLabel>
          <BarChart
            data={chartData}
            series={[{ key: "net", label: "Net" }]}
            xKey="date"
            height={140}
            diverging
            onSelect={(d) => goToDate(d.x)}
          />
        </div>

        <div>
          <ChartLabel>Daily Breakdown</ChartLabel>
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-xs text-muted-foreground">
                <th className="py-2 text-left font-medium">Date</th>
                <th className="py-2 text-right font-medium">Income</th>
                <th className="py-2 text-right font-medium">Spend</th>
                <th className="py-2 text-right font-medium">Net</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {[...days].reverse().filter(d => d.spend > 0 || d.income > 0).map((d) => {
                const dayNet = d.income - d.spend;
                return (
                  <tr key={d.date} className="text-sm">
                    <td className="py-2.5">
                      <button onClick={() => goToDate(d.date)}
                        className="rounded text-primary hover:underline tabular-nums focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
                        {d.date}
                      </button>
                    </td>
                    <td className="py-2.5 text-right tabular-nums">{d.income > 0 ? formatCurrency(d.income) : <span className="opacity-30">—</span>}</td>
                    <td className="py-2.5 text-right tabular-nums">{d.spend > 0 ? formatCurrency(d.spend) : <span className="opacity-30">—</span>}</td>
                    <td className={cn("py-2.5 text-right tabular-nums font-medium", moneyColor(dayNet))}>
                      {dayNet >= 0 ? "+" : ""}{formatCurrency(dayNet)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
