import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { X } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/PageState";
import type { MerchantSummary } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

export function MerchantsSettings() {
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const { data: merchants = [], isLoading, isError, refetch } = useQuery(queries.merchants());

  const exclude = useMutation({
    mutationFn: (id: string) => api.post(`/merchants/${id}/exclude`, {}),
    onSuccess: () => invalidate(qc, keys.merchants),
  });

  const include = useMutation({
    mutationFn: (id: string) => api.post(`/merchants/${id}/include`, {}),
    onSuccess: () => invalidate(qc, keys.merchants),
  });

  const q = search.trim().toLowerCase();
  const excluded = (merchants as MerchantSummary[]).filter((m) => m.excluded);
  const active   = (merchants as MerchantSummary[]).filter((m) => !m.excluded && (q === "" || m.name.toLowerCase().includes(q)));

  return (
    <div className="space-y-6">
      <p className="text-sm text-muted-foreground">
        Excluded merchants are hidden from spending reports, charts, and totals.
      </p>

      {excluded.length > 0 && (
        <div>
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Excluded ({excluded.length})
          </p>
          <Card>
            <CardContent className="p-0">
              <ul className="divide-y text-sm">
                {excluded.map((m) => (
                  <li key={m.id} className="flex items-center justify-between px-4 py-2.5">
                    <span className="font-medium line-through text-muted-foreground">{m.name}</span>
                    <Button
                      variant="ghost"
                      size="xs"
                      onClick={() => include.mutate(m.id)}
                      className="ml-3 gap-1 text-muted-foreground hover:text-foreground"
                    >
                      <X size={11} /> Remove
                    </Button>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
        </div>
      )}

      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          All Merchants
        </p>
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search merchants…"
          aria-label="Search merchants"
          className="mb-3 h-8"
        />
        {isLoading ? (
          <SkeletonList rows={5} rowClassName="h-10 rounded-lg" className="space-y-1" />
        ) : isError ? (
          <ErrorState title="Failed to load merchants" onRetry={() => refetch()} />
        ) : active.length === 0 ? (
          <EmptyState
            title={q ? "No merchants match your search." : "All merchants are excluded."}
            className="py-4"
          />
        ) : (
          <Card>
            <CardContent className="p-0">
              <ul className="divide-y text-sm">
                {active.map((m) => (
                  <li key={m.id} className="flex items-center justify-between px-4 py-2.5">
                    <div className="min-w-0">
                      <p className="font-medium truncate">{m.name}</p>
                      {m.category_name && (
                        <p className="text-xs text-muted-foreground">{m.category_name}</p>
                      )}
                    </div>
                    <Button
                      variant="outline"
                      size="xs"
                      onClick={() => exclude.mutate(m.id)}
                      className="ml-3 shrink-0 font-normal text-muted-foreground hover:text-foreground"
                    >
                      Exclude
                    </Button>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
