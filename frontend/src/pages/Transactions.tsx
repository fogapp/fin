import { useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import { useAllTransactions } from "@/hooks/useAllTransactions";
import { ResponsiveTransactionView as TransactionTable } from "@/components/TransactionList";
import { PageHeader } from "@/components/layout/PageHeader";
import { Card, CardContent } from "@/components/ui/card";
import { ErrorState } from "@/components/PageState";
import type { ActiveFilter } from "@/components/FilterBar";

/** Chart drill-down URL params → visible FilterBar pills. */
function filtersFromSearchParams(params: URLSearchParams): ActiveFilter[] {
  const filters: ActiveFilter[] = [];
  let key = 0;
  const push = (field: string, operator: string, value: string | null) => {
    if (value) filters.push({ _key: ++key, field, operator, value });
  };
  push("transaction_date", "gte", params.get("start_date"));
  push("transaction_date", "lte", params.get("end_date"));
  push("category_id", "equals", params.get("category_id"));
  push("merchant_id", "equals", params.get("merchant_id"));
  push("source", "equals", params.get("source"));
  return filters;
}

export function Transactions() {
  const [searchParams] = useSearchParams();
  const urlFilters = useMemo(() => filtersFromSearchParams(searchParams), [searchParams]);
  // tag/excluded-tags/account/category-group have no FilterBar pill — they scope the query
  // server-side.
  const serverFilters = useMemo(() => {
    const f: Record<string, string> = {};
    for (const key of ["tag_id", "exclude_tag_ids", "account_id", "category_ids"] as const) {
      const value = searchParams.get(key);
      if (value) f[key] = value;
    }
    return f;
  }, [searchParams]);

  const { transactions, isLoading, isError, refetch } = useAllTransactions(serverFilters);

  return (
    <div className="flex h-full flex-col overflow-hidden">
      <PageHeader title="Transactions" level={1} />

      <div className="flex-1 overflow-y-auto pb-16 md:pb-0">
        {isError ? (
          <ErrorState title="Failed to load transactions" onRetry={refetch} />
        ) : (
          <Card className="rounded-none border-0 shadow-none">
            <CardContent className="p-0">
              <TransactionTable
                transactions={transactions}
                isLoading={isLoading}
                columns={["date", "description", "merchant", "category", "account", "amount"]}
                initialFilters={urlFilters}
                resetKey={searchParams.toString()}
              />
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
