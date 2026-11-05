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

export function AlchemyCredentialsForm({ onDone }: { onDone: () => void }) {
  const qc = useQueryClient();
  const { data: config, isLoading } = useQuery(queries.alchemyConfiguration());
  const [apiKey, setApiKey] = useState("");
  const [authToken, setAuthToken] = useState("");
  const [baseUrl, setBaseUrl] = useState<string | null>(null);

  const effectiveBaseUrl = baseUrl ?? config?.webhook_base_url ?? "";

  const saveConfig = useMutation({
    mutationFn: () =>
      api.patch("/alchemy/configuration", {
        alchemy_configuration: {
          ...(apiKey ? { api_key: apiKey } : {}),
          ...(authToken ? { auth_token: authToken } : {}),
          ...(baseUrl !== null ? { webhook_base_url: baseUrl.trim() } : {}),
        },
      }),
    onSuccess: () => {
      invalidate(qc, keys.alchemyConfiguration, keys.alchemyWallets);
      setApiKey("");
      setAuthToken("");
      setBaseUrl(null);
      onDone();
    },
  });

  if (isLoading) return <SkeletonList rows={2} rowClassName="h-9 rounded-lg" />;

  return (
    <div className="space-y-4">
      {config && (
        <div className="space-y-2 rounded-lg border bg-muted/30 px-4 py-3">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">API key</span>
            {config.api_key_set
              ? <span className="text-positive">Configured</span>
              : <span className="text-muted-foreground">Not set</span>}
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Notify auth token</span>
            {config.auth_token_set
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
          <Label htmlFor="alchemy-api-key">API key</Label>
          <Input
            id="alchemy-api-key"
            type="password"
            placeholder={config?.api_key_set ? "Leave blank to keep current" : "Paste your Alchemy API key"}
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            className="font-mono text-sm"
            autoComplete="new-password"
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="alchemy-auth-token">Notify auth token</Label>
          <Input
            id="alchemy-auth-token"
            type="password"
            placeholder={config?.auth_token_set ? "Leave blank to keep current" : "Required for real-time webhooks"}
            value={authToken}
            onChange={(e) => setAuthToken(e.target.value)}
            className="font-mono text-sm"
            autoComplete="new-password"
          />
          <p className="text-xs text-muted-foreground">
            From the Alchemy dashboard (Webhooks → Auth token). Only needed for real-time sync.
          </p>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="alchemy-base-url">Public base URL</Label>
          <Input
            id="alchemy-base-url"
            type="text"
            placeholder={config?.suggested_webhook_base_url ?? "https://your-domain.example"}
            value={effectiveBaseUrl}
            onChange={(e) => setBaseUrl(e.target.value)}
            className="font-mono text-sm"
            autoComplete="off"
          />
          <p className="text-xs text-muted-foreground">
            Where Alchemy delivers webhooks — this app's HTTPS address as reachable from the internet.
          </p>
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
