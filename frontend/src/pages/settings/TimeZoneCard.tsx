import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Globe } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { keys } from "@/api/keys";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { SkeletonList } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/toast";
import { ErrorState } from "@/components/PageState";
import { EntityCombobox } from "@/components/EntityCombobox";
import type { InstanceSettings, SelectableTimeZone } from "@/api/types";

// ── Time zone ─────────────────────────────────────────────────────────────────
// Instance-wide, not per household: "today", month boundaries, the nightly
// schedule and workflow schedules all run in it. Household admins change it;
// everyone else sees it read-only. The zone list comes from the API so every
// option is one the server accepts.

function zoneLabel(zone: SelectableTimeZone): string {
  return zone.id.replace(/_/g, " ");
}

export function TimeZoneCard({ isAdmin }: { isAdmin: boolean }) {
  const qc = useQueryClient();
  const { data, isLoading, isError, refetch } = useQuery(queries.instanceSettings());
  const current = data?.time_zone;
  const zones = data?.time_zones ?? [];

  const update = useMutation({
    mutationFn: (timeZone: string) => api.patch<InstanceSettings>("/instance_settings", { time_zone: timeZone }),
    onSuccess: (res) => {
      qc.setQueryData(keys.instanceSettings, res);
      // Every date the server computed ("today", this month) may have moved.
      qc.invalidateQueries();
      toast.success(`Time zone set to ${res.time_zone}`);
    },
    onError: (err: Error) => toast.error(err.message),
  });

  const selected = zones.find((z) => z.id === current) ?? (current ? { id: current, name: null, utc_offset: "" } : null);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base font-semibold text-foreground">
          <Globe size={16} />
          Time zone
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading && <SkeletonList rows={1} />}
        {isError && <ErrorState title="Failed to load the time zone" onRetry={() => refetch()} />}
        {!isLoading && !isError && current && (
          isAdmin ? (
            <div className="space-y-1.5">
              <Label htmlFor="instance-time-zone">Zone</Label>
              <EntityCombobox<SelectableTimeZone>
                value={current}
                onChange={(id) => { if (id && id !== current) update.mutate(id); }}
                items={zones}
                selectedItem={selected}
                getId={(z) => z.id}
                getLabel={zoneLabel}
                filter={(z, query) =>
                  z.id.toLowerCase().replace(/_/g, " ").includes(query) ||
                  (z.name ?? "").toLowerCase().includes(query) ||
                  z.utc_offset.includes(query)}
                renderOption={(z) => (
                  <>
                    <span className="min-w-0 flex-1 truncate">{zoneLabel(z)}</span>
                    {z.name && <span className="truncate text-xs text-muted-foreground">{z.name}</span>}
                    <span className="shrink-0 font-mono text-xs tabular-nums text-muted-foreground">UTC{z.utc_offset}</span>
                  </>
                )}
                ariaLabel="Time zone"
                placeholder="Search time zones…"
                emptyMessage="No matching time zone."
                className="max-w-md"
              />
            </div>
          ) : (
            <div className="flex items-baseline justify-between gap-4">
              <span className="text-sm text-muted-foreground">Zone</span>
              <span className="text-sm font-medium">{selected ? zoneLabel(selected) : current}</span>
            </div>
          )
        )}
        <p className="text-xs text-muted-foreground">
          Applies to the whole Fin instance, every household: what counts as today and this month,
          and when the nightly syncs and scheduled workflows run.
          {!isAdmin && " Only a household admin can change it."}
        </p>
      </CardContent>
    </Card>
  );
}
