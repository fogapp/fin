import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Trash2, CheckCircle, X, Plus, BookOpen } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FieldError } from "@/components/ui/field";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { useConfirm } from "@/components/ui/confirm";
import { ErrorState } from "@/components/PageState";
import { formatDate } from "@/lib/utils";
import { invalidate, keys } from "@/api/keys";

export function ApiTokens() {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const { data: tokens = [], isLoading, isError, refetch } = useQuery(queries.apiTokens());

  const [showForm, setShowForm] = useState(false);
  const [name, setName] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [newToken, setNewToken] = useState<{ id: string; name: string; token: string } | null>(null);
  const [copied, setCopied] = useState(false);

  const createToken = useMutation({
    mutationFn: () => api.post<{ id: string; name: string; token: string }>("/api_tokens", {
      name: name.trim() || null,
      expires_at: expiresAt || null,
    }),
    onSuccess: (data) => {
      invalidate(qc, keys.apiTokens);
      setNewToken(data);
      setName("");
      setExpiresAt("");
      setShowForm(false);
    },
  });

  const deleteToken = useMutation({
    mutationFn: (id: string) => api.delete(`/api_tokens/${id}`),
    onSuccess: () => invalidate(qc, keys.apiTokens),
  });

  function copyToken(token: string) {
    navigator.clipboard.writeText(token);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className="space-y-4">
      {/* One-time token reveal */}
      {newToken && (
        <div className="rounded-lg border bg-card p-4 space-y-3">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-sm font-medium text-foreground">
                {newToken.name ? `"${newToken.name}" created` : "Token created"}
              </p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Make sure to copy your token now — it won't be shown again.
              </p>
            </div>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => setNewToken(null)}
              aria-label="Dismiss"
              className="shrink-0 text-muted-foreground hover:text-foreground"
            >
              <X size={15} />
            </Button>
          </div>
          <div className="flex items-center gap-2">
            <code className="flex-1 rounded bg-muted px-3 py-2 text-xs font-mono text-foreground break-all select-all">
              {newToken.token}
            </code>
            <Button size="sm" variant="outline" onClick={() => copyToken(newToken.token)} aria-label="Copy token" className="shrink-0">
              {copied ? <CheckCircle size={13} className="text-positive" /> : "Copy"}
            </Button>
          </div>
        </div>
      )}

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <CardTitle className="text-base font-semibold text-foreground">API Tokens</CardTitle>
              <a
                href={`${window.location.origin}/api-docs`}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
              >
                <BookOpen size={12} />
                API docs
              </a>
            </div>
            {!showForm && (
              <Button size="sm" variant="outline" onClick={() => setShowForm(true)}>
                <Plus size={13} />
                New token
              </Button>
            )}
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Create form */}
          {showForm && (
            <form
              onSubmit={(e) => { e.preventDefault(); createToken.mutate(); }}
              className="rounded-lg border bg-muted/30 p-4 space-y-3"
            >
              <p className="text-sm font-medium">New token</p>
              <div className="flex gap-3">
                <div className="flex-1 space-y-1">
                  <Label htmlFor="api-token-name">Name <span className="font-normal">(optional)</span></Label>
                  <Input
                    id="api-token-name"
                    placeholder="e.g. CI pipeline, local dev"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    className="text-sm"
                    autoComplete="off"
                  />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="api-token-expires">Expires <span className="font-normal">(optional)</span></Label>
                  <Input
                    id="api-token-expires"
                    type="date"
                    value={expiresAt}
                    onChange={(e) => setExpiresAt(e.target.value)}
                    className="text-sm w-40 tabular-nums"
                  />
                </div>
              </div>
              <div className="flex gap-2">
                <Button type="button" size="sm" variant="ghost" onClick={() => { setShowForm(false); setName(""); setExpiresAt(""); }}>
                  Cancel
                </Button>
                <Button type="submit" size="sm" disabled={createToken.isPending}>
                  {createToken.isPending ? "Creating…" : "Create token"}
                </Button>
              </div>
              {createToken.isError && (
                <FieldError>Failed to create token. Please try again.</FieldError>
              )}
            </form>
          )}

          {isLoading && <SkeletonList rows={2} />}
          {isError && <ErrorState title="Failed to load tokens" onRetry={() => refetch()} />}
          {!showForm && !isLoading && !isError && tokens.length === 0 && (
            <EmptyState
              title="No tokens yet."
              description="Create one to call the Fin API from scripts or CI."
              className="py-6"
            />
          )}
          {tokens.length > 0 && (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-xs text-muted-foreground">
                  <th className="pb-2 text-left font-medium">Name</th>
                  <th className="pb-2 text-left font-medium">Scope</th>
                  <th className="pb-2 text-left font-medium">Last used</th>
                  <th className="pb-2 text-left font-medium">Expires</th>
                  <th className="pb-2 text-left font-medium">Created</th>
                  <th />
                </tr>
              </thead>
              <tbody className="divide-y">
                {tokens.map((t) => (
                  <tr key={t.id}>
                    <td className="py-2.5 font-medium">{t.name ?? <span className="text-muted-foreground italic">Unnamed</span>}</td>
                    <td className="py-2.5">
                      {/* A read-only token is one fog minted for another app, or
                          one made from a console; the UI only makes full ones. */}
                      {t.scope === "read"
                        ? <Badge variant="outline" title="Can read Fin, not change it">Read-only</Badge>
                        : <span className="text-muted-foreground">Full</span>}
                    </td>
                    <td className="py-2.5 text-muted-foreground">{t.last_used_at ? formatDate(t.last_used_at) : "Never"}</td>
                    <td className="py-2.5 text-muted-foreground">
                      {t.expires_at
                        ? <span className={new Date(t.expires_at) < new Date() ? "text-destructive" : ""}>{formatDate(t.expires_at)}</span>
                        : "Never"}
                    </td>
                    <td className="py-2.5 text-muted-foreground">{formatDate(t.created_at)}</td>
                    <td className="py-2.5 text-right">
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        aria-label="Delete token"
                        className="text-destructive hover:bg-destructive/10 hover:text-destructive"
                        onClick={async () => {
                          if (await confirm({
                            title: `Delete token${t.name ? ` "${t.name}"` : ""}?`,
                            confirmLabel: "Delete",
                            destructive: true,
                          })) deleteToken.mutate(t.id);
                        }}
                      >
                        <Trash2 size={13} />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
