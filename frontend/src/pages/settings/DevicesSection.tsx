import { useState, useEffect } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Trash2, Fingerprint, Pencil, Copy, Check, Plus } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { formatDate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { FieldError } from "@/components/ui/field";
import { ErrorState } from "@/components/PageState";
import { SettingsSection, SettingsSubsection } from "./SettingsSection";
import type { DeviceInvite, WebauthnCredential } from "@/api/types";
import { invalidate, keys } from "@/api/keys";


function InviteLink({ token, expiresAt, onDismiss }: { token: string; expiresAt: string; onDismiss: () => void }) {
  const url = `${window.location.origin}/join-device?token=${encodeURIComponent(token)}`;
  const [copied, setCopied] = useState(false);
  const [secondsLeft, setSecondsLeft] = useState(() =>
    Math.max(0, Math.round((new Date(expiresAt).getTime() - Date.now()) / 1000))
  );

  useEffect(() => {
    const id = setInterval(() => {
      setSecondsLeft((s) => {
        if (s <= 1) { clearInterval(id); onDismiss(); return 0; }
        return s - 1;
      });
    }, 1000);
    return () => clearInterval(id);
  }, [onDismiss]);

  function copy() {
    navigator.clipboard.writeText(url);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  const mins = Math.floor(secondsLeft / 60);
  const secs = secondsLeft % 60;

  return (
    <div className="rounded-lg border border-primary/20 bg-primary/5 p-4 space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium">Device invite link</p>
        <span className="text-xs text-muted-foreground tabular-nums">
          Expires in {mins}:{secs.toString().padStart(2, "0")}
        </span>
      </div>
      <p className="text-xs text-muted-foreground">
        Open this link on your new device. It expires in 15 minutes and can only be used once.
      </p>
      <div className="flex items-center gap-2">
        <code className="flex-1 truncate rounded-md bg-muted px-3 py-2 text-xs font-mono">
          {url}
        </code>
        <Button variant="outline" size="sm" onClick={copy} className="shrink-0 gap-1.5 bg-card">
          {copied ? <Check size={12} className="text-positive" /> : <Copy size={12} />}
          {copied ? "Copied" : "Copy"}
        </Button>
      </div>
      <Button variant="ghost" size="xs" onClick={onDismiss} className="text-muted-foreground hover:text-foreground">
        Dismiss
      </Button>
    </div>
  );
}

export function DevicesSection() {
  const qc = useQueryClient();
  const { data: creds = [], isLoading, isError, refetch } = useQuery(queries.webauthnCredentials());
  const [invite, setInvite] = useState<DeviceInvite | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editNickname, setEditNickname] = useState("");
  const [renameError, setRenameError] = useState("");

  const refresh = () => invalidate(qc, keys.webauthnCredentials);

  const remove = useMutation({
    mutationFn: (id: string) => api.delete(`/webauthn_credentials/${id}`),
    onSuccess: refresh,
  });

  // Rename only — the API refuses a blank nickname, so Save stays disabled
  // rather than firing a request that can only fail.
  const rename = useMutation({
    mutationFn: ({ id, nickname }: { id: string; nickname: string }) =>
      api.patch<WebauthnCredential>(`/webauthn_credentials/${id}`, { nickname }),
    onSuccess: () => { refresh(); setEditingId(null); setRenameError(""); },
    onError: (err: Error) => setRenameError(err.message),
  });

  const generateInvite = useMutation({
    mutationFn: () => api.post<DeviceInvite>("/device_invites", {}),
    onSuccess: (data) => setInvite(data),
  });

  function startEdit(cred: WebauthnCredential) {
    setEditingId(cred.id);
    setEditNickname(cred.nickname ?? "");
    setRenameError("");
  }

  return (
    <SettingsSection
      title="Devices"
      description="Passkeys registered to your account. Each device needs its own passkey to sign in."
    >
      <SettingsSubsection label="Registered passkeys">
        {isLoading ? (
          <SkeletonList rows={2} rowClassName="h-14 rounded-lg" className="space-y-2" />
        ) : isError ? (
          <ErrorState title="Failed to load passkeys" onRetry={() => refetch()} />
        ) : (
          <div className="divide-y rounded-lg border">
            {creds.map((cred) => (
              <div key={cred.id} className="flex items-center gap-3 px-4 py-3">
                <Fingerprint size={16} className="shrink-0 text-muted-foreground" />
                <div className="min-w-0 flex-1">
                  {editingId === cred.id ? (
                    <div>
                      <form
                        onSubmit={(e) => {
                          e.preventDefault();
                          if (!editNickname.trim()) return;
                          rename.mutate({ id: cred.id, nickname: editNickname });
                        }}
                        className="flex items-center gap-2"
                      >
                        <Input
                          autoFocus
                          value={editNickname}
                          onChange={(e) => { setEditNickname(e.target.value); setRenameError(""); }}
                          placeholder="Device name"
                          aria-label="Device name"
                          className="h-7 flex-1 px-2.5"
                        />
                        <Button type="button" variant="ghost" size="xs" onClick={() => setEditingId(null)}>
                          Cancel
                        </Button>
                        <Button type="submit" size="xs" disabled={rename.isPending || !editNickname.trim()}>
                          Save
                        </Button>
                      </form>
                      <FieldError className="mt-1">
                        {renameError || (editNickname.trim() ? null : "A passkey needs a name — register a new one instead.")}
                      </FieldError>
                    </div>
                  ) : (
                    <>
                      <p className="truncate text-sm font-medium">
                        {cred.nickname ?? <span className="text-muted-foreground italic">Unnamed device</span>}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Added {formatDate(cred.created_at)}
                        {cred.last_used_at && ` · Last used ${formatDate(cred.last_used_at)}`}
                      </p>
                    </>
                  )}
                </div>
                {editingId !== cred.id && (
                  <div className="flex items-center gap-1 shrink-0">
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => startEdit(cred)}
                      title="Rename"
                      aria-label="Rename"
                      className="text-muted-foreground hover:text-foreground"
                    >
                      <Pencil size={13} />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => remove.mutate(cred.id)}
                      disabled={remove.isPending || creds.length <= 1}
                      title={creds.length <= 1 ? "Cannot remove your only passkey" : "Remove"}
                      aria-label="Remove"
                      className="text-destructive hover:bg-destructive/10 hover:text-destructive"
                    >
                      <Trash2 size={13} />
                    </Button>
                  </div>
                )}
              </div>
            ))}
            {creds.length === 0 && (
              <EmptyState title="No passkeys registered." className="py-6" />
            )}
          </div>
        )}
      </SettingsSubsection>

      <SettingsSubsection
        label="Add a device"
        description="Generate a one-time link and open it on your new device to register a passkey for it."
      >
        {invite ? (
          <InviteLink
            token={invite.token}
            expiresAt={invite.expires_at}
            onDismiss={() => setInvite(null)}
          />
        ) : (
          <Button
            variant="outline"
            onClick={() => generateInvite.mutate()}
            disabled={generateInvite.isPending}
            className="gap-1.5 border-dashed text-muted-foreground hover:text-foreground"
          >
            <Plus size={14} />
            {generateInvite.isPending ? "Generating…" : "Generate invite link"}
          </Button>
        )}
      </SettingsSubsection>
    </SettingsSection>
  );
}
