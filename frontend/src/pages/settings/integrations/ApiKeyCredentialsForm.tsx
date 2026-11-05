import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FieldError } from "@/components/ui/field";
import { SkeletonList } from "@/components/ui/skeleton";
import type { ApiKeyProviderDescriptor } from "./apiKeyProviders";
import { invalidate } from "@/api/keys";

/** Shared key-entry form for the simple API-key providers, driven by the descriptor table. */
export function ApiKeyCredentialsForm({
  provider,
  onDone,
}: {
  provider: ApiKeyProviderDescriptor;
  onDone: () => void;
}) {
  const qc = useQueryClient();
  const { data: config, isLoading } = useQuery(provider.query());
  const [apiKey, setApiKey] = useState("");
  const [extra, setExtra] = useState("");
  const [text, setText] = useState("");
  const { numberField, textField } = provider;
  // A required text field (Office's instance URL) is only satisfied once the
  // config carries one, or this form supplies it.
  const textSatisfied = !textField?.required || !!text.trim() || !!textField.current?.(config);

  const saveConfig = useMutation({
    mutationFn: () =>
      api.patch(provider.configPath, {
        [provider.paramKey]: {
          ...(apiKey ? { api_key: apiKey } : {}),
          ...(textField && text.trim() ? { [textField.paramKey]: text.trim() } : {}),
          ...(numberField && extra ? { [numberField.paramKey]: extra } : {}),
        },
      }),
    onSuccess: () => {
      invalidate(qc, ...provider.invalidateKeys);
      setApiKey("");
      setExtra("");
      setText("");
      onDone();
    },
  });

  if (isLoading) return <SkeletonList rows={2} rowClassName="h-9 rounded-lg" />;

  return (
    <div className="space-y-4">
      {config && (
        <div className="rounded-lg border bg-muted/30 px-4 py-3">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">{provider.keyLabel ?? "API Key"}</span>
            {config.api_key_set
              ? <span className="text-positive">
                  {config.source === "environment" ? "Set in the environment" : "Configured"}
                </span>
              : <span className="text-muted-foreground">Not set</span>}
          </div>
        </div>
      )}
      <form onSubmit={(e) => { e.preventDefault(); saveConfig.mutate(); }} className="space-y-4">
        {textField && (
          <div className="space-y-1.5">
            <Label htmlFor={textField.id}>{textField.label}</Label>
            <Input
              id={textField.id}
              type="url"
              placeholder={textField.current?.(config) || textField.placeholder}
              value={text}
              onChange={(e) => setText(e.target.value)}
              autoComplete="off"
            />
            {textField.help && <p className="text-xs text-muted-foreground">{textField.help}</p>}
          </div>
        )}
        <div className="space-y-1.5">
          <Label htmlFor={provider.inputId}>{provider.keyLabel ?? "API Key"}</Label>
          <Input
            id={provider.inputId}
            type="password"
            placeholder={config?.api_key_set ? "Leave blank to keep current" : provider.keyPlaceholder}
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            className="font-mono text-sm"
            autoComplete="off"
          />
        </div>
        {numberField && (
          <div className="space-y-1.5">
            <Label htmlFor={numberField.id}>{numberField.label}</Label>
            <Input
              id={numberField.id}
              type="number"
              min={numberField.min}
              placeholder={numberField.placeholder(config)}
              value={extra}
              onChange={(e) => setExtra(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">{numberField.help}</p>
          </div>
        )}
        <Button
          type="submit"
          disabled={
            saveConfig.isPending ||
            !textSatisfied ||
            (!apiKey && !extra && !text.trim() && !config?.api_key_set)
          }
        >
          {saveConfig.isPending ? "Saving…" : "Save"}
        </Button>
        {saveConfig.isError && (
          <FieldError className="text-sm">Failed to save. Please try again.</FieldError>
        )}
      </form>
    </div>
  );
}
