import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Store } from "lucide-react";
import { MasterDetailShell, MasterDetailLoading } from "@/components/MasterDetailShell";
import { InlineCreateForm } from "@/components/InlineCreateForm";
import { queries } from "@/api/queries";
import { Card, CardContent } from "@/components/ui/card";
import { ErrorState } from "@/components/PageState";
import { PageHeader } from "@/components/layout/PageHeader";
import { SpendByMonthTable } from "@/components/SpendByMonthTable";
import { ResponsiveTransactionView as TransactionTable } from "@/components/TransactionList";
import { StatRibbon } from "@/components/StatRibbon";
import { ChartLabel } from "@/components/charts";
import { SpendChartCard } from "@/components/spend-chart";
import { formatCurrency, fillLastMonths } from "@/lib/utils";
import { keys } from "@/api/keys";

export function Merchants() {
  const { data: merchants = [], isLoading, isError, refetch } = useQuery(queries.merchants());

  return (
    <MasterDetailShell
      title="Merchants"
      noun="merchant"
      nounPlural="merchants"
      icon={Store}
      items={merchants}
      isLoading={isLoading}
      isError={isError}
      refetch={refetch}
      renderNewForm={({ onCreated, onCancel }) => (
        <InlineCreateForm endpoint="/merchants" invalidateKey={keys.merchants} placeholder="Merchant name" onCreated={onCreated} onCancel={onCancel} />
      )}
      rowCount={(merchant) => merchant.transaction_count}
      renderDetail={(id) => <MerchantDetail id={id} />}
    />
  );
}

// ── MerchantDetail ────────────────────────────────────────────────────────────

function MerchantDetail({ id }: { id: string }) {
  const { data, isLoading, error, refetch } = useQuery(queries.merchant(id));
  const { data: transactions = [], isLoading: txLoading, isError: txError, refetch: refetchTx } =
    useQuery(queries.merchantTransactions(id));

  if (isLoading) return <MasterDetailLoading />;
  if (error || !data) return (
    <ErrorState title="Failed to load merchant" onRetry={() => refetch()} />
  );

  const spendData  = fillLastMonths(data.monthly_spend);
  const incomeData = fillLastMonths(data.monthly_income);

  const totalSpend  = spendData.reduce((s, d) => s + d.amount, 0);
  const totalIncome = incomeData.reduce((s, d) => s + d.amount, 0);

  return (
    <div className="flex flex-col">
      <PageHeader title={data.name} subtitle={data.notes ?? undefined}>
        {data.category_id && (
          <Link
            to={`/categories#id=${data.category_id}`}
            className="rounded text-xs text-muted-foreground hover:text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            {data.category_name}
          </Link>
        )}
      </PageHeader>

      <StatRibbon borderTop={false} stats={[
        ...(totalSpend > 0 ? [{ label: "Total Spend", value: formatCurrency(totalSpend) }] : []),
        ...(totalIncome > 0 ? [{ label: "Total Income", value: formatCurrency(totalIncome) }] : []),
      ]} />

      <div className="space-y-6 p-6">
        {/* Canonical spend chart, merchant-scoped — drills into /transactions
            for this merchant + month */}
        <div>
          <ChartLabel>Monthly Spend</ChartLabel>
          <SpendChartCard variant="compact" scope={{ merchantId: id }} height={160} />
        </div>

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
                    columns={["date", "description", "category", "amount"]}
                    resetKey={id}
                    exportScope={{ merchant_id: id }}
                  />
                )}
              </CardContent>
            </Card>
          </div>

          <div className="space-y-6">
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
