import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Settings2, Trash2 } from "lucide-react";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useConfirm } from "@/components/ui/confirm";
import type { ApiKeyProviderDescriptor } from "./apiKeyProviders";
import { invalidate } from "@/api/keys";
import { useTestConnection } from "./useTestConnection";
import { TestResultBanner } from "./TestResultBanner";

/** Shared connected-provider pane for the simple API-key providers. */
export function ApiKeyProviderDetail({
  provider,
  onEditCredentials,
  onRemoved,
}: {
  provider: ApiKeyProviderDescriptor;
  onEditCredentials: () => void;
  onRemoved: () => void;
}) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const { remove, DetailExtra } = provider;

  const testConnection = useTestConnection(provider.configPath, {
    // Some providers' test endpoint spends a request — pull the counter back in.
    onTested: provider.testRefetchesConfig ? () => invalidate(qc, ...provider.invalidateKeys) : undefined,
  });

  const removeConnection = useMutation({
    mutationFn: () => api.delete(provider.configPath),
    onSuccess: () => {
      invalidate(qc, ...provider.invalidateKeys);
      onRemoved();
    },
  });

  const handleRemove = async () => {
    if (!remove) return;
    const ok = await confirm({
      title: remove.confirmTitle,
      description: remove.confirmDescription,
      confirmLabel: "Remove",
      destructive: true,
    });
    if (ok) removeConnection.mutate();
  };

  return (
    <div>
      <div className="bg-gradient-to-r from-primary/10 via-primary/5 to-transparent border-b px-8 py-8">
        <div className="flex items-center gap-2 mb-3">
          <Badge variant="success">Connected</Badge>
        </div>
        <h2 className="text-base font-semibold text-foreground">{provider.name}</h2>
        <p className="text-sm text-muted-foreground mt-1">{provider.detailBlurb}</p>
      </div>

      {DetailExtra && <DetailExtra />}

      <div className="px-8 py-5 border-b">
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">Actions</p>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm"
            onClick={testConnection.test}
            disabled={testConnection.isPending}
          >
            {testConnection.isPending ? "Testing…" : provider.testLabel ?? "Test connection"}
          </Button>
          <Button variant="outline" size="sm" onClick={onEditCredentials}>
            <Settings2 size={13} />
            Edit credentials
          </Button>
          {remove && (
            <Button variant="outline" size="sm" onClick={handleRemove} disabled={removeConnection.isPending}>
              <Trash2 size={13} />
              {removeConnection.isPending ? "Removing…" : "Remove"}
            </Button>
          )}
        </div>
        {provider.testNote && (
          <p className="mt-2 text-xs text-muted-foreground">{provider.testNote}</p>
        )}
        <TestResultBanner result={testConnection.result} />
      </div>
    </div>
  );
}
