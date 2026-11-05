import { useQuery } from "@tanstack/react-query";
import { Tags as TagsIcon } from "lucide-react";
import { MasterDetailShell, MasterDetailLoading } from "@/components/MasterDetailShell";
import { InlineCreateForm } from "@/components/InlineCreateForm";
import { queries } from "@/api/queries";
import { Card, CardContent } from "@/components/ui/card";
import { KeyValueTable } from "@/components/ui/key-value-table";
import { ErrorState } from "@/components/PageState";
import { PageHeader } from "@/components/layout/PageHeader";
import { SpendByMonthTable } from "@/components/SpendByMonthTable";
import { ResponsiveTransactionView as TransactionTable } from "@/components/TransactionList";
import { StatRibbon } from "@/components/StatRibbon";
import { ChartLabel } from "@/components/charts";
import { usePageTimeframe } from "@/hooks/useTimeframeButtons";
import { SpendChartCard, useSpendChartControls } from "@/components/spend-chart";
import { formatCurrency, fillLastMonths } from "@/lib/utils";
import { mtdVsProratedPrior } from "@/lib/statFormat";
import { keys } from "@/api/keys";

export function Tags() {
  const { data: tags = [], isLoading, isError, refetch } = useQuery(queries.tags());

  return (
    <MasterDetailShell
      title="Tags"
      noun="tag"
      nounPlural="tags"
      icon={TagsIcon}
      items={tags}
      isLoading={isLoading}
      isError={isError}
      refetch={refetch}
      renderNewForm={({ onCreated, onCancel }) => (
        <InlineCreateForm endpoint="/tags" invalidateKey={keys.tags} placeholder="Tag name" onCreated={onCreated} onCancel={onCancel} />
      )}
      rowCount={(tag) => tag.transaction_count ?? 0}
      renderDetail={(id) => <TagDetail id={id} />}
    />
  );
}

function TagDetail({ id }: { id: string }) {
  const { data, isLoading, error, refetch } = useQuery(queries.tag(id));
  const { data: transactions = [], isLoading: txLoading, isError: txError, refetch: refetchTx } =
    useQuery(queries.tagTransactions(id));
  // The spend chart manages its own window and modes — this page has no
  // page-level header scoping anything beyond the chart.
  const timeframe = usePageTimeframe("tags", "tag-spend-timeframe");
  const chartControls = useSpendChartControls();

  if (isLoading) return <MasterDetailLoading />;
  if (error || !data) return <ErrorState title="Failed to load tag" onRetry={() => refetch()} />;

  const spendData = fillLastMonths(data.monthly_spend);

  const categoryData = Object.entries(data.by_category)
    .slice(0, 10)
    .map(([name, amount]) => ({ name, amount }));

  // MTD vs prorated prior month
  const { mtd: mtdSpend, change: mtdChange } = mtdVsProratedPrior(spendData);

  return (
    <div className="flex flex-col">
      <PageHeader title={data.name} />

      <StatRibbon borderTop={false} stats={[
        { label: "Transactions", value: data.total_count.toLocaleString() },
        { label: "Total Spend",  value: formatCurrency(data.total_spend) },
        ...(mtdSpend > 0 ? [{ label: "MTD", value: formatCurrency(mtdSpend), change: mtdChange, invertColor: true }] : []),
        ...(data.total_returns > 0 ? [{ label: "Returns", value: formatCurrency(data.total_returns) }] : []),
      ]} />

      <div className="space-y-6 p-6">

      {/* Spend chart — the shared segmented spend card, scoped to this tag:
          Total / by-Category / by-Merchant splits, $ / %, outlier modes, and
          its own timeframe. Clicking a month drills into /transactions
          filtered to the tag and month. */}
      <SpendChartCard
        scope={{ tagId: id }}
        timeframe={timeframe}
        controls={chartControls}
        showSeriesToggle
        showTimeframeSelector
      />


      {/* Two-column: transactions + right sidebar */}
      <div className="grid gap-6 lg:grid-cols-[1fr_240px]">
        <div>
          <ChartLabel>Transactions</ChartLabel>
          <Card>
            <CardContent className="p-0">
              {txError ? (
                <ErrorState title="Failed to load transactions" onRetry={() => refetchTx()} />
              ) : (
                <TransactionTable
                  transactions={transactions}
                  isLoading={txLoading}
                  columns={["date", "description", "merchant", "category", "amount"]}
                  resetKey={id}
                  exportScope={{ tag_id: id }}
                />
              )}
            </CardContent>
          </Card>
        </div>

        <div className="space-y-6">
          {categoryData.length > 0 && (
            <div>
              <ChartLabel>By Category</ChartLabel>
              <KeyValueTable
                header={{ label: "Category", value: "Spend" }}
                rows={categoryData.map(({ name, amount }) => ({
                  key: name,
                  label: name,
                  value: formatCurrency(amount),
                }))}
              />
            </div>
          )}

          {spendData.length > 0 && (
            <div>
              <ChartLabel>Spend by Month</ChartLabel>
              <SpendByMonthTable data={spendData} />
            </div>
          )}
        </div>
      </div>
    </div>
    </div>
  );
}
