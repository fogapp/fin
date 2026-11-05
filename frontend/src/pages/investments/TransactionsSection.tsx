import { useQuery, useQueryClient } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { InvestmentTransactionTable } from "@/components/InvestmentTransactionTable";
import { SectionLoading } from "./SectionLayout";
import { invalidate, keys } from "@/api/keys";

// ── Investments › Transactions ────────────────────────────────────────────────
// Every investment transaction across all accounts, as one table. The table
// owns filtering, sorting, grouping, paging, and the detail drawer; this
// section only fetches and frames it.

export function TransactionsSection() {
  const qc = useQueryClient();
  const { data, isLoading, refetch } = useQuery(queries.allInvestmentTransactions());

  if (isLoading) return <SectionLoading />;
  if (!data) return <ErrorState title="Failed to load transactions" onRetry={() => refetch()} />;

  return (
    <div className="flex flex-col">
      <PageHeader
        title="Transactions"
        subtitle={`${data.length.toLocaleString()} investment transaction${data.length === 1 ? "" : "s"} across all accounts`}
      />
      <div className="border-t">
        <InvestmentTransactionTable
          transactions={data}
          showSecurity
          onReprocessed={() => invalidate(qc, keys.investmentTransactions)}
        />
      </div>
    </div>
  );
}
