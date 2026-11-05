import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { FieldError } from "@/components/ui/field";
import { SkeletonList } from "@/components/ui/skeleton";
import type { PlaidConfiguration } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

const PLAID_ENVIRONMENTS = ["sandbox", "production"] as const;

export function PlaidCredentialsForm({ onDone }: { onDone: () => void }) {
  const qc = useQueryClient();
  const { data: config, isLoading } = useQuery(queries.plaidConfiguration());
  const [clientId, setClientId] = useState("");
  const [secret, setSecret] = useState("");
  const [environment, setEnvironment] = useState<PlaidConfiguration["environment"]>("production");

  const saveConfig = useMutation({
    mutationFn: () =>
      api.patch("/plaid/configuration", {
        plaid_configuration: {
          ...(clientId ? { client_id: clientId } : {}),
          ...(secret   ? { secret }              : {}),
          environment,
        },
      }),
    onSuccess: () => {
      invalidate(qc, keys.plaidConfiguration);
      setClientId("");
      setSecret("");
      onDone();
    },
  });

  if (isLoading) return <SkeletonList rows={4} rowClassName="h-9 rounded-lg" />;

  return (
    <div className="space-y-4">
      {config && (
        <div className="space-y-2 rounded-lg border bg-muted/30 px-4 py-3">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Environment</span>
            <Badge variant="outline" className="capitalize">{config.environment}</Badge>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Client ID</span>
            {config.client_id_set
              ? <span className="text-positive">Configured</span>
              : <span className="text-muted-foreground">Using env variable</span>}
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Secret</span>
            {config.secret_set
              ? <span className="text-positive">Configured</span>
              : <span className="text-muted-foreground">Using env variable</span>}

          </div>
        </div>
      )}

      <form
        onSubmit={(e) => { e.preventDefault(); saveConfig.mutate(); }}
        className="space-y-4"
      >
        <div className="space-y-1.5">
          <Label htmlFor="plaid-environment">Environment</Label>
          <Select
            id="plaid-environment"
            value={environment}
            onChange={(e) => setEnvironment(e.target.value as PlaidConfiguration["environment"])}
          >
            {PLAID_ENVIRONMENTS.map((env) => (
              <option key={env} value={env}>{env}</option>
            ))}
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="plaid-client-id">Client ID</Label>
          <Input
            id="plaid-client-id"
            type="text"
            placeholder={config?.client_id_set ? "Leave blank to keep current" : "Enter client ID"}
            value={clientId}
            onChange={(e) => setClientId(e.target.value)}
            className="font-mono text-sm"
            autoComplete="off"
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="plaid-secret">Secret</Label>
          <Input
            id="plaid-secret"
            type="password"
            placeholder={config?.secret_set ? "Leave blank to keep current" : "Enter secret"}
            value={secret}
            onChange={(e) => setSecret(e.target.value)}
            className="font-mono text-sm"
            autoComplete="new-password"
          />
        </div>
        <div className="flex gap-2">
          <Button type="submit" size="sm" disabled={saveConfig.isPending}>
            {saveConfig.isPending ? "Saving…" : "Save"}
          </Button>
        </div>
        {saveConfig.isError && (
          <FieldError className="text-sm">Failed to save. Please try again.</FieldError>
        )}
      </form>
    </div>
  );
}
