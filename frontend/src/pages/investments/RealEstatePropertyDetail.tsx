import { useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { ArrowLeft, Trash2, Plus } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { formatCurrency, formatDate } from "@/lib/utils";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon } from "@/components/StatRibbon";
import { ChartCard, ChartLabel, LineChart } from "@/components/charts";
import { KeyValueTable } from "@/components/ui/key-value-table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Field } from "@/components/ui/field";
import { Skeleton } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/PageState";
import { useConfirm } from "@/components/ui/confirm";
import { toast } from "@/components/ui/toast";
import type { PageAction } from "@/components/layout/PageHeader";
import type { RealEstatePropertyDetail, RealEstateValuation, RealEstateValuationSource } from "@/api/types";
import { RefreshButton } from "./RealEstateSection";
import { invalidate, keys } from "@/api/keys";

const SOURCE_LABEL: Record<RealEstateValuationSource, string> = {
  rentcast:       "RentCast estimate",
  manual:         "Manual entry",
  purchase:       "Purchase price",
  sale:           "Recorded sale",
  tax_assessment: "Tax assessed",
};

const MARKET_SOURCES: RealEstateValuationSource[] = ["rentcast", "manual", "purchase", "sale"];

export function PropertyDetail({ id, onBack }: { id: string; onBack: () => void }) {
  const { data: property, isLoading, isError, refetch } = useQuery(queries.realEstateProperty(id));
  const deleteAction = useDeletePropertyAction(id, property, onBack);

  // Two lines on one x-axis: market value (what the property is worth) and
  // assessed value (what the county says, which runs below market by a ratio
  // that varies — so it's a reference, never the number we count).
  const chartData = useMemo(() => {
    if (!property) return [];
    const byDate = new Map<string, { date: string; market?: number; assessed?: number }>();

    for (const valuation of property.valuations) {
      const row = byDate.get(valuation.as_of) ?? { date: valuation.as_of };
      if (valuation.source === "tax_assessment") row.assessed = valuation.amount;
      else row.market = valuation.amount;
      byDate.set(valuation.as_of, row);
    }

    return [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date));
  }, [property]);

  if (isLoading) return <LoadingState />;
  if (isError || !property) return <ErrorState title="Failed to load property" onRetry={() => refetch()} />;

  const hasAssessments = chartData.some((row) => row.assessed !== undefined);
  const { facts } = property;

  return (
    <div className="flex flex-col">
      <PageHeader title={property.name} subtitle={property.display_address} actions={[ deleteAction ]}>
        <div className="flex items-center gap-2">
          {property.sync_enabled && property.status !== "sold" && <RefreshButton id={property.id} />}
          <Button variant="outline" size="sm" onClick={onBack}>
            <ArrowLeft size={13} />
            All properties
          </Button>
        </div>
      </PageHeader>

      <StatRibbon borderTop={false} stats={[
        { label: "Value",    value: formatCurrency(property.value) },
        { label: "Mortgage", value: property.mortgage_balance === null ? "—" : formatCurrency(property.mortgage_balance) },
        { label: "Equity",   value: property.equity === null ? "—" : formatCurrency(property.equity), highlight: "positive" },
        { label: "LTV",      value: property.loan_to_value === null ? "—" : `${property.loan_to_value}%` },
        { label: "Purchase", value: property.purchase_price === null ? "—" : formatCurrency(property.purchase_price), dividerBefore: true },
      ]} />

      <div className="space-y-6 p-6">
        <ChartCard title="Value history">
          {chartData.length > 1 ? (
            <>
              <LineChart
                data={chartData}
                xKey="date"
                series={
                  hasAssessments
                    ? [{ key: "market", label: "Market value" }, { key: "assessed", label: "Tax assessed" }]
                    : [{ key: "market", label: "Market value" }]
                }
                height={240}
                yFormat={(v) => formatCurrency(v, true)}
              />
              {hasAssessments && (
                <p className="mt-2 text-xs text-muted-foreground">
                  Assessed values come from county tax records and typically run below market value.
                  They&rsquo;re shown for reference and are never used as the property&rsquo;s value.
                </p>
              )}
            </>
          ) : (
            <EmptyState
              title="Not enough history yet."
              description="Values accumulate as they're recorded — one point per weekly sync, plus anything you enter."
            />
          )}
        </ChartCard>

        <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
          <div>
            <ChartLabel>Valuations</ChartLabel>
            <ValuationTable propertyId={property.id} valuations={property.valuations} />
            <AddValuationForm propertyId={property.id} />
          </div>

          <div className="space-y-6">
            <div>
              <ChartLabel>Property</ChartLabel>
              <KeyValueTable
                mutedLabels
                rows={[
                  { key: "type",  label: "Type",        value: facts.property_type ?? "—" },
                  { key: "beds",  label: "Bedrooms",    value: facts.bedrooms?.toString() ?? "—" },
                  { key: "baths", label: "Bathrooms",   value: facts.bathrooms?.toString() ?? "—" },
                  { key: "sqft",  label: "Square feet", value: facts.square_footage?.toLocaleString() ?? "—" },
                  { key: "lot",   label: "Lot size",    value: facts.lot_size?.toLocaleString() ?? "—" },
                  { key: "built", label: "Year built",  value: facts.year_built?.toString() ?? "—" },
                  { key: "hoa",   label: "HOA fee",     value: facts.hoa_fee === null ? "—" : formatCurrency(facts.hoa_fee) },
                ]}
              />
            </div>

            {property.mortgages.length > 0 && (
              <div>
                <ChartLabel>Mortgages</ChartLabel>
                <div className="space-y-2">
                  {property.mortgages.map((mortgage) => (
                    <Link
                      key={mortgage.id}
                      to={`/loans/${mortgage.id}`}
                      className="block rounded-lg border px-3 py-2 text-sm transition-colors hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                    >
                      <p className="font-medium">{mortgage.name}</p>
                      {mortgage.lender && <p className="text-xs text-muted-foreground">{mortgage.lender}</p>}
                    </Link>
                  ))}
                </div>
              </div>
            )}

            <div>
              <ChartLabel>Sync</ChartLabel>
              <KeyValueTable
                mutedLabels
                rows={[
                  { key: "auto",  label: "Automatic", value: property.sync_enabled ? "On" : "Off" },
                  { key: "last",  label: "Last synced", value: property.last_synced_at ? formatDate(property.last_synced_at) : "Never" },
                  ...(property.last_sync_error
                    ? [{ key: "err", label: "Last error", value: property.last_sync_error }]
                    : []),
                ]}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function useDeletePropertyAction(
  id: string,
  property: RealEstatePropertyDetail | undefined,
  onDeleted: () => void,
): PageAction {
  const qc = useQueryClient();
  const confirm = useConfirm();

  const destroy = useMutation({
    mutationFn: () => api.delete(`/real_estate_properties/${id}`),
    onSuccess: () => {
      // Drop the detail entry before invalidating the list so the prefix
      // match doesn't refetch a property that no longer exists.
      qc.removeQueries({ queryKey: queries.realEstateProperty(id).queryKey });
      invalidate(qc, keys.realEstateProperties, keys.loans, keys.netWorth);
      toast.success(property ? `${property.name} deleted` : "Property deleted");
      onDeleted();
    },
    onError: (e: Error) => toast.error(e.message),
  });

  return {
    label: "Delete property",
    icon: Trash2,
    destructive: true,
    disabled: destroy.isPending,
    onSelect: async () => {
      const linked = property?.mortgages.length ?? 0;
      if (await confirm({
        title: property ? `Delete ${property.name}?` : "Delete this property?",
        description:
          "The property and its valuation history are removed, and it drops out of net worth." +
          (linked > 0 ? ` Its linked mortgage${linked === 1 ? " is" : "s are"} kept, just unlinked.` : ""),
        confirmLabel: "Delete property",
        destructive: true,
      })) {
        destroy.mutate();
      }
    },
  };
}

function ValuationTable({ propertyId, valuations }: { propertyId: string; valuations: RealEstateValuation[] }) {
  const qc = useQueryClient();
  const confirm = useConfirm();

  const remove = useMutation({
    mutationFn: (valuationId: string) =>
      api.delete(`/real_estate_properties/${propertyId}/valuations/${valuationId}`),
    onSuccess: () => {
      invalidate(qc, keys.realEstateProperties, keys.netWorth);
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const handleRemove = async (valuation: RealEstateValuation) => {
    const ok = await confirm({
      title: "Delete this valuation?",
      description: `${formatCurrency(valuation.amount)} on ${formatDate(valuation.as_of)} will be removed from the history.`,
      confirmLabel: "Delete",
      destructive: true,
    });
    if (ok) remove.mutate(valuation.id);
  };

  if (valuations.length === 0) {
    return <EmptyState title="No valuations recorded yet." />;
  }

  // Newest first — the current value is what you're usually checking.
  const rows = [...valuations].sort((a, b) => b.as_of.localeCompare(a.as_of));

  return (
    <div className="overflow-hidden rounded-xl border">
      <table className="w-full text-sm">
        <thead className="border-b bg-muted/30 text-xs text-muted-foreground">
          <tr>
            <th className="px-3 py-2 text-left font-medium">Date</th>
            <th className="px-3 py-2 text-left font-medium">Source</th>
            <th className="px-3 py-2 text-right font-medium">Value</th>
            <th className="w-10 px-3 py-2" />
          </tr>
        </thead>
        <tbody>
          {rows.map((valuation) => (
            <tr key={valuation.id} className="border-b last:border-0">
              <td className="px-3 py-2 tabular-nums">{formatDate(valuation.as_of)}</td>
              <td className="px-3 py-2">
                <span className="flex items-center gap-2">
                  {SOURCE_LABEL[valuation.source]}
                  {!MARKET_SOURCES.includes(valuation.source) && <Badge variant="outline">Reference</Badge>}
                </span>
                {valuation.value_low !== null && valuation.value_high !== null && (
                  <span className="text-xs text-muted-foreground">
                    Range {formatCurrency(valuation.value_low, true)}–{formatCurrency(valuation.value_high, true)}
                  </span>
                )}
              </td>
              <td className="px-3 py-2 text-right tabular-nums">{formatCurrency(valuation.amount)}</td>
              <td className="px-3 py-2">
                <button
                  onClick={() => handleRemove(valuation)}
                  aria-label={`Delete ${formatDate(valuation.as_of)} valuation`}
                  className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-destructive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  <Trash2 size={13} />
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function AddValuationForm({ propertyId }: { propertyId: string }) {
  const qc = useQueryClient();
  const [amount, setAmount] = useState("");
  const [asOf, setAsOf] = useState("");

  const add = useMutation({
    mutationFn: () =>
      api.post(`/real_estate_properties/${propertyId}/valuations`, {
        amount,
        ...(asOf ? { as_of: asOf } : {}),
      }),
    onSuccess: () => {
      invalidate(qc, keys.realEstateProperties, keys.netWorth);
      setAmount("");
      setAsOf("");
      toast.success("Valuation recorded");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <form
      onSubmit={(e) => { e.preventDefault(); add.mutate(); }}
      className="mt-4 flex flex-wrap items-end gap-3"
    >
      <Field label="Value" htmlFor="re-add-amount" className="w-40">
        <Input id="re-add-amount" type="number" step="any" placeholder="950000" value={amount}
          onChange={(e) => setAmount(e.target.value)} />
      </Field>
      <Field label="As of" htmlFor="re-add-date" className="w-44">
        <Input id="re-add-date" type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} />
      </Field>
      <Button type="submit" size="sm" className="mb-5" disabled={!amount || add.isPending}>
        <Plus size={13} />
        {add.isPending ? "Adding…" : "Add valuation"}
      </Button>
      <p className="mb-5 text-xs text-muted-foreground">
        Defaults to today. The newest date wins, and a value you enter beats an estimate recorded the same day.
      </p>
    </form>
  );
}

function LoadingState() {
  return (
    <div className="space-y-4 p-6">
      <Skeleton className="h-6 w-40" />
      <Skeleton className="h-10 rounded-xl" />
      <Skeleton className="h-64 rounded-xl" />
    </div>
  );
}
