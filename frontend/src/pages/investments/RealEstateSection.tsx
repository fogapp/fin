import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { Home, Plus, RefreshCw, AlertCircle } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon } from "@/components/StatRibbon";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Field, FieldError } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { toast } from "@/components/ui/toast";
import type { RealEstateProperty, RealEstateValuationSource } from "@/api/types";
import { PropertyDetail } from "./RealEstatePropertyDetail";
import { invalidate, keys } from "@/api/keys";

/** Human label for the badge on a property's current value. */
const SOURCE_LABEL: Record<RealEstateValuationSource, string> = {
  rentcast:       "RentCast",
  manual:         "Manual",
  purchase:       "Purchase price",
  sale:           "Recorded sale",
  tax_assessment: "Tax assessed",
};

export function RealEstateSection() {
  const [showForm, setShowForm] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);
  const { data, isLoading, isError, refetch } = useQuery(queries.realEstateProperties());

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState title="Failed to load real estate" onRetry={() => refetch()} />;

  const { properties, totals, rentcast } = data;
  const selected = properties.find((p) => p.id === openId) ?? null;

  if (selected) {
    return <PropertyDetail id={selected.id} onBack={() => setOpenId(null)} />;
  }

  return (
    <div className="flex flex-col">
      {/* Inline rather than in the page-actions dropdown: adding the second
          property is the common case, and the pencil menu sits at the far
          right of the header among the shell's own controls, where it reads
          as chrome rather than as this section's action. When the list is
          empty the EmptyState carries the CTA instead. */}
      <PageHeader
        title="Real Estate"
        subtitle={totals.count > 0 ? `${totals.count} propert${totals.count === 1 ? "y" : "ies"}` : undefined}
      >
        {properties.length > 0 && !showForm && (
          <Button size="sm" onClick={() => setShowForm(true)}>
            <Plus size={14} />
            Add property
          </Button>
        )}
      </PageHeader>

      {properties.length > 0 && (
        <StatRibbon borderTop={false} stats={[
          { label: "Total Value", value: formatCurrency(totals.value, true) },
          { label: "Mortgages",   value: formatCurrency(totals.mortgage, true) },
          { label: "Equity",      value: formatCurrency(totals.equity, true), highlight: "positive" },
        ]} />
      )}

      <div className="space-y-4 p-6">
        {!rentcast.configured && <ConnectBanner />}

        {rentcast.configured && rentcast.remaining_quota !== null && (
          <QuotaNote remaining={rentcast.remaining_quota} limit={rentcast.request_limit} />
        )}

        {showForm && (
          <PropertyForm
            rentcastConfigured={rentcast.configured}
            onDone={() => setShowForm(false)}
          />
        )}

        {properties.length === 0 && !showForm && (
          <EmptyState
            icon={Home}
            title="No properties yet."
            description={
              rentcast.configured
                ? "Add an address and RentCast will value it, then keep it updated weekly."
                : "Add an address and enter its value. Connect RentCast to have it valued automatically."
            }
            action={
              <Button size="sm" onClick={() => setShowForm(true)}>
                <Plus size={14} />
                Add property
              </Button>
            }
          />
        )}

        {properties.map((property) => (
          <PropertyCard key={property.id} property={property} onOpen={() => setOpenId(property.id)} />
        ))}
      </div>
    </div>
  );
}

function ConnectBanner() {
  return (
    <div className="rounded-xl border bg-muted/30 px-5 py-4">
      <p className="text-sm font-medium">Value properties automatically</p>
      <p className="mt-1 text-xs text-muted-foreground">
        Connect RentCast in{" "}
        <Link to="/settings#section=integrations" className="text-primary underline underline-offset-2">
          Settings → Integrations
        </Link>{" "}
        and each property is valued weekly, with tax-assessment and sale history seeded from public records.
        Until then, enter values by hand — everything else works the same.
      </p>
    </div>
  );
}

/** Surfaces a tight allowance before the weekly sync silently skips a run. */
function QuotaNote({ remaining, limit }: { remaining: number; limit: number }) {
  if (remaining > 6) return null;

  return (
    <div className="flex items-start gap-2 rounded-xl border bg-muted/30 px-5 py-4">
      <AlertCircle size={14} className="mt-0.5 shrink-0 text-muted-foreground" />
      <p className="text-xs text-muted-foreground">
        {remaining} of {limit} RentCast requests left this month. The weekly sync is skipped when the
        remaining allowance can&rsquo;t cover every property, so values may go stale until it resets.
      </p>
    </div>
  );
}

function PropertyCard({ property, onOpen }: { property: RealEstateProperty; onOpen: () => void }) {
  const equityPct =
    property.value && property.value > 0 && property.equity !== null
      ? Math.max(0, Math.min(100, (property.equity / property.value) * 100))
      : null;

  return (
    <button
      onClick={onOpen}
      className="group w-full rounded-xl border bg-card p-5 text-left transition-colors hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="truncate font-medium">{property.name}</p>
          <p className="truncate text-xs text-muted-foreground">{property.display_address}</p>
        </div>
        <div className="shrink-0 text-right">
          <p className="text-lg font-semibold tabular-nums">{formatCurrency(property.value)}</p>
          <p className="text-caption text-muted-foreground">
            {property.value_source ? SOURCE_LABEL[property.value_source] : "No value yet"}
            {property.value_as_of && ` · ${formatDate(property.value_as_of)}`}
          </p>
        </div>
      </div>

      {property.mortgage_balance !== null && (
        <div className="mt-4">
          <div className="flex items-center justify-between text-xs">
            <span className="text-muted-foreground">
              Equity {formatCurrency(property.equity)}
              {property.loan_to_value !== null && ` · ${property.loan_to_value}% LTV`}
            </span>
            <span className="text-muted-foreground">
              Mortgage {formatCurrency(property.mortgage_balance)}
            </span>
          </div>
          {equityPct !== null && (
            <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-muted">
              <div className="h-full rounded-full bg-primary" style={{ width: `${equityPct}%` }} />
            </div>
          )}
        </div>
      )}

      <div className="mt-3 flex flex-wrap items-center gap-2">
        {property.status === "sold" && <Badge variant="outline">Sold</Badge>}
        {!property.sync_enabled && property.status !== "sold" && <Badge variant="outline">Manual</Badge>}
        {property.last_sync_error && (
          <span className="inline-flex items-center gap-1 text-caption text-destructive">
            <AlertCircle size={11} />
            {property.last_sync_error}
          </span>
        )}
      </div>
    </button>
  );
}

function PropertyForm({ rentcastConfigured, onDone }: { rentcastConfigured: boolean; onDone: () => void }) {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    name: "", address_line1: "", city: "", state: "", zip_code: "",
    purchase_price: "", purchase_date: "", value: "",
  });
  const [error, setError] = useState<string | null>(null);

  const create = useMutation({
    mutationFn: () =>
      api.post<RealEstateProperty>("/real_estate_properties", {
        name:           form.name,
        address_line1:  form.address_line1,
        city:           form.city || undefined,
        state:          form.state || undefined,
        zip_code:       form.zip_code || undefined,
        purchase_price: form.purchase_price || undefined,
        purchase_date:  form.purchase_date || undefined,
        value:          form.value || undefined,
      }),
    onSuccess: (property) => {
      invalidate(qc, keys.realEstateProperties, keys.netWorth);
      toast.success(
        property.value !== null
          ? `${property.name} added at ${formatCurrency(property.value)}`
          : `${property.name} added — enter a value to include it in net worth`
      );
      onDone();
    },
    onError: (e: Error) => setError(e.message),
  });

  const canSubmit = form.name.trim() !== "" && form.address_line1.trim() !== "" &&
    (rentcastConfigured || form.value.trim() !== "");

  return (
    <form
      onSubmit={(e) => { e.preventDefault(); setError(null); create.mutate(); }}
      className="space-y-4 rounded-xl border bg-card p-5"
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Name" required htmlFor="re-name">
          <Input id="re-name" placeholder="Primary residence" value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })} />
        </Field>
        <Field label="Street address" required htmlFor="re-address">
          <Input id="re-address" placeholder="5500 Grand Lake Dr" value={form.address_line1}
            onChange={(e) => setForm({ ...form, address_line1: e.target.value })} />
        </Field>
        <Field label="City" htmlFor="re-city">
          <Input id="re-city" value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} />
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="State" htmlFor="re-state">
            <Input id="re-state" placeholder="TX" value={form.state}
              onChange={(e) => setForm({ ...form, state: e.target.value })} />
          </Field>
          <Field label="ZIP" htmlFor="re-zip">
            <Input id="re-zip" placeholder="78244" value={form.zip_code}
              onChange={(e) => setForm({ ...form, zip_code: e.target.value })} />
          </Field>
        </div>
        <Field label="Purchase price" htmlFor="re-purchase-price">
          <Input id="re-purchase-price" type="number" step="any" placeholder="720000" value={form.purchase_price}
            onChange={(e) => setForm({ ...form, purchase_price: e.target.value })} />
        </Field>
        <Field label="Purchase date" htmlFor="re-purchase-date">
          <Input id="re-purchase-date" type="date" value={form.purchase_date}
            onChange={(e) => setForm({ ...form, purchase_date: e.target.value })} />
        </Field>
        <Field
          label={rentcastConfigured ? "Current value (optional)" : "Current value"}
          required={!rentcastConfigured}
          htmlFor="re-value"
        >
          <Input id="re-value" type="number" step="any" placeholder="912000" value={form.value}
            onChange={(e) => setForm({ ...form, value: e.target.value })} />
        </Field>
      </div>

      <p className="text-xs text-muted-foreground">
        {rentcastConfigured
          ? "RentCast is looked up on save — that costs two requests, and seeds the value, property facts, tax-assessment history and recorded sales."
          : "Without RentCast connected, the value you enter here is the property's value until you update it."}
      </p>

      <FieldError>{error}</FieldError>

      <div className="flex gap-2">
        <Button type="submit" size="sm" disabled={!canSubmit || create.isPending}>
          {create.isPending ? "Adding…" : "Add property"}
        </Button>
        <Button type="button" variant="outline" size="sm" onClick={onDone}>Cancel</Button>
      </div>
    </form>
  );
}

/** Shared by the section and the detail view. */
export function RefreshButton({ id, disabled }: { id: string; disabled?: boolean }) {
  const qc = useQueryClient();
  const refresh = useMutation({
    mutationFn: () => api.post(`/real_estate_properties/${id}/refresh`, {}),
    onSuccess: () => {
      invalidate(qc, keys.realEstateProperties, keys.rentcastConfiguration, keys.netWorth);
      toast.success("Value refreshed from RentCast");
    },
    onError: (e: Error) => toast.error(e.message),
  });

  return (
    <Button variant="outline" size="sm" disabled={disabled || refresh.isPending} onClick={() => refresh.mutate()}>
      <RefreshCw size={13} className={cn(refresh.isPending && "animate-spin")} />
      {refresh.isPending ? "Refreshing…" : "Refresh now"}
    </Button>
  );
}

function LoadingState() {
  return (
    <div className="space-y-4 p-6">
      <Skeleton className="h-6 w-32" />
      <Skeleton className="h-10 rounded-xl" />
      <Skeleton className="h-32 rounded-xl" />
      <Skeleton className="h-32 rounded-xl" />
    </div>
  );
}
