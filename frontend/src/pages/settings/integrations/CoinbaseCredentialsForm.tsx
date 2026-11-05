import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FieldError } from "@/components/ui/field";
import { SkeletonList } from "@/components/ui/skeleton";
import { invalidate, keys } from "@/api/keys";

export function CoinbaseCredentialsForm({ onDone }: { onDone: () => void }) {
  const qc = useQueryClient();
  const { data: config, isLoading } = useQuery(queries.coinbaseConfiguration());
  const [keyId, setKeyId] = useState("");
  const [keySecret, setKeySecret] = useState("");

  const saveConfig = useMutation({
    mutationFn: () =>
      api.patch("/coinbase/configuration", {
        coinbase_configuration: {
          ...(keyId     ? { api_key_id:     keyId     } : {}),
          ...(keySecret ? { api_key_secret: keySecret } : {}),
        },
      }),
    onSuccess: () => {
      invalidate(qc, keys.coinbaseConfiguration, keys.coinbaseAccounts);
      setKeyId("");
      setKeySecret("");
      onDone();
    },
  });

  if (isLoading) return <SkeletonList rows={3} rowClassName="h-9 rounded-lg" />;

  return (
    <div className="space-y-4">
      {config && (
        <div className="space-y-2 rounded-lg border bg-muted/30 px-4 py-3">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">API Key ID</span>
            {config.api_key_id_set
              ? <span className="text-positive">Configured</span>
              : <span className="text-muted-foreground">Not set</span>}
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Secret</span>
            {config.api_key_secret_set
              ? <span className="text-positive">Configured</span>
              : <span className="text-muted-foreground">Not set</span>}
          </div>
        </div>
      )}

      <form
        onSubmit={(e) => { e.preventDefault(); saveConfig.mutate(); }}
        className="space-y-4"
      >
        <div className="space-y-1.5">
          <Label htmlFor="coinbase-key-id">API Key ID</Label>
          <Input
            id="coinbase-key-id"
            type="text"
            placeholder={config?.api_key_id_set ? "Leave blank to keep current" : "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}
            value={keyId}
            onChange={(e) => setKeyId(e.target.value)}
            className="font-mono text-sm"
            autoComplete="off"
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="coinbase-secret">Secret</Label>
          <Input
            id="coinbase-secret"
            type="password"
            placeholder={config?.api_key_secret_set ? "Leave blank to keep current" : "Paste your secret"}
            value={keySecret}
            onChange={(e) => setKeySecret(e.target.value)}
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
