import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon } from "@/components/StatRibbon";
import { KeyValueTable } from "@/components/ui/key-value-table";
import {
  ChartLabel, ChartCard, BarChart, TimeframeSelector, transactionsHref, type Timeframe,
} from "@/components/charts";
import { formatCurrency, fillMonthsFrom } from "@/lib/utils";
import { ScopeFilter, type CashflowScopeState } from "./ScopeFilter";
import { ReportViews } from "./ReportViews";
import type { CashflowData } from "@/api/types";

export function IncomeSection({ data, timeframe, scope, onScopeChange }: {
  data: CashflowData;
  timeframe: Timeframe;
  scope: CashflowScopeState;
  onScopeChange: (next: CashflowScopeState) => void;
}) {
  const { summary: s, monthly_income, monthly_spend, top_income_sources } = data;

  const incomeByMonth = fillMonthsFrom(monthly_income, timeframe.from);
  const spendByMonth  = fillMonthsFrom(monthly_spend, timeframe.from);

  const netData = incomeByMonth.map((d, i) => ({
    month:  d.month,
    income: d.amount,
    net:    +(d.amount - (spendByMonth[i]?.amount ?? 0)).toFixed(2),
  }));

  const avgMonthlyIncome = incomeByMonth.reduce((sum, d) => sum + d.amount, 0) / Math.max(incomeByMonth.length, 1);
  const mtdChange = s.lmo_income > 0 ? ((s.mtd_income - s.lmo_income) / s.lmo_income) * 100 : null;

  return (
    <div className="flex flex-col">
      <PageHeader title="Income" sticky>
        <ScopeFilter value={scope} onChange={onScopeChange} />
        <ReportViews timeframe={timeframe} scope={scope} onScopeChange={onScopeChange} />
      </PageHeader>

      <StatRibbon borderTop={false} stats={[
        { label: "MTD",          value: formatCurrency(s.mtd_income),       change: mtdChange },
        { label: "Last Month",   value: formatCurrency(s.lmo_income) },
        { label: "YTD",          value: formatCurrency(s.ytd_income, true), dividerBefore: true },
        { label: "Avg / Month",  value: formatCurrency(avgMonthlyIncome) },
        { label: "Savings Rate", value: s.savings_rate_ytd != null ? `${s.savings_rate_ytd.toFixed(1)}%` : "—",
          highlight: (s.savings_rate_ytd ?? 0) >= 0 ? "positive" : "negative" },
      ]} />

      <div className="space-y-6 p-6">
        {/* Monthly income — the page-scoped timeframe control lives in the
            primary chart card's header */}
        <ChartCard
          title="Monthly Income"
          control={<TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />}
        >
          <BarChart
            data={netData}
            series={[{ key: "income", label: "Income" }]}
            height={200}
            linkFor={(d) => transactionsHref({ month: d.x })}
          />
        </ChartCard>

        {/* Net cashflow — diverging bars (positive/negative polarity) */}
        <ChartCard title="Net Cashflow">
          <BarChart
            data={netData}
            series={[{ key: "net", label: "Net" }]}
            height={140}
            diverging
            linkFor={(d) => transactionsHref({ month: d.x })}
          />
        </ChartCard>

        {/* Income sources */}
        {Object.keys(top_income_sources).length > 0 && (
          <div>
            <ChartLabel>Income Sources — YTD</ChartLabel>
            <KeyValueTable
              rows={Object.entries(top_income_sources).map(([name, amount]) => ({
                key: name,
                label: name,
                value: formatCurrency(amount),
                valueClassName: "text-positive",
              }))}
            />
          </div>
        )}
      </div>
    </div>
  );
}
