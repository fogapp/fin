import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { AlertCircle, Archive, Check, Copy, Download, KeyRound, Link2, Loader2, Trash2 } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";
import { formatBytes, formatDateTime } from "@/lib/utils";
import { downloadText, downloadUrl } from "@/lib/download";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FieldError } from "@/components/ui/field";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { useConfirm } from "@/components/ui/confirm";
import { ErrorState } from "@/components/PageState";
import { SettingsSection, SettingsSubsection } from "./SettingsSection";
import type { Backup, BackupDownload, BackupKeys, BackupOverview, DeviceInvite, HouseholdMember } from "@/api/types";

const DESCRIPTION =
  "A backup is a single file holding this whole instance: every account, transaction, rule and setting. " +
  "Restoring it into a fresh Fin brings everything back, at this address or a new one.";

export function BackupSection() {
  const { data: me } = useQuery(queries.me());

  // A backup holds everyone's data, so the server only serves admins — say
  // so here rather than showing a member a failed request. Nothing is asked
  // of the server until the role is known.
  if (!me || me.household.role !== "admin") {
    return (
      <SettingsSection title="Backup" description={DESCRIPTION}>
        {me ? (
          <p className="rounded-lg border px-4 py-3 text-sm text-muted-foreground">
            Only a household admin can create and download backups.
          </p>
        ) : (
          <SkeletonList rows={3} rowClassName="h-14 rounded-lg" className="space-y-2" />
        )}
      </SettingsSection>
    );
  }

  return <BackupPanels meUserId={me.user.id} />;
}

function BackupPanels({ meUserId }: { meUserId: string }) {
  const { data, isLoading, isError, error, refetch } = useQuery(queries.backups());

  return (
    <SettingsSection title="Backup" description={DESCRIPTION}>
      {isLoading ? (
        <SkeletonList rows={3} rowClassName="h-14 rounded-lg" className="space-y-2" />
      ) : isError || !data ? (
        <ErrorState title="Backups aren't available" message={error?.message} onRetry={() => refetch()} />
      ) : (
        <>
          <RestoreNote restore={data.last_restore} />
          <BackupList overview={data} />
          <InstanceKeys overview={data} />
          <MoveLinks host={data.address.host} meUserId={meUserId} />
          <RestoreSteps />
        </>
      )}
    </SettingsSection>
  );
}

// ── Where this instance came from ─────────────────────────────────────────────

function RestoreNote({ restore }: { restore: BackupOverview["last_restore"] }) {
  if (!restore?.restored_at) return null;

  return (
    <p className="rounded-lg border bg-muted/30 px-4 py-3 text-sm text-muted-foreground">
      This instance was restored on {formatDateTime(restore.restored_at)}
      {restore.artifact_created_at && <> from a backup taken {formatDateTime(restore.artifact_created_at)}</>}
      {restore.moved_from && restore.moved_to && (
        <>, moving from <span className="font-mono text-foreground">{restore.moved_from}</span> to{" "}
        <span className="font-mono text-foreground">{restore.moved_to}</span></>
      )}
      .
    </p>
  );
}

// ── Backups ───────────────────────────────────────────────────────────────────

function BackupList({ overview }: { overview: BackupOverview }) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const refresh = () => invalidate(qc, keys.backups);
  const running = overview.backups.some((b) => b.status === "running");

  const create = useMutation({
    mutationFn: () => api.post<Backup>("/backups"),
    onSuccess: refresh,
  });

  // The artifact can run to gigabytes, so it goes through the browser's own
  // download rather than fetch: the server trades the session for a URL that
  // works for a few minutes without a bearer header.
  const download = useMutation({
    mutationFn: (id: string) => api.post<BackupDownload>(`/backups/${id}/download`),
    onSuccess: ({ url }) => downloadUrl(url),
  });

  const remove = useMutation({
    mutationFn: (id: string) => api.delete(`/backups/${id}`),
    onSuccess: refresh,
  });

  return (
    <SettingsSubsection
      label="Backups"
      description={`A backup stays on the server for ${overview.retention_hours} hours, then is removed. Download the ones you want to keep.`}
    >
      {overview.backups.length === 0 ? (
        <div className="rounded-lg border">
          <EmptyState icon={Archive} title="No backups yet." description="Create one to download a copy of this instance." className="py-8" />
        </div>
      ) : (
        <div className="divide-y rounded-lg border">
          {overview.backups.map((backup) => (
            <BackupRow
              key={backup.id}
              backup={backup}
              downloading={download.isPending && download.variables === backup.id}
              onDownload={() => download.mutate(backup.id)}
              onRemove={async () => {
                if (await confirm({
                  title: "Delete this backup?",
                  description: "It is removed from the server. Copies you already downloaded are not affected.",
                  confirmLabel: "Delete",
                  destructive: true,
                })) remove.mutate(backup.id);
              }}
            />
          ))}
        </div>
      )}
      <Button onClick={() => create.mutate()} disabled={running || create.isPending} className="gap-1.5">
        <Archive size={14} />
        {running || create.isPending ? "Creating backup…" : "Create backup"}
      </Button>
    </SettingsSubsection>
  );
}

function BackupRow({ backup, downloading, onDownload, onRemove }: {
  backup: Backup;
  downloading: boolean;
  onDownload: () => void;
  onRemove: () => void;
}) {
  if (backup.status === "running") {
    return (
      <div className="flex items-center gap-3 px-4 py-3">
        <Loader2 size={16} className="shrink-0 animate-spin text-primary" />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium">Creating backup…</p>
          <p className="text-xs text-muted-foreground first-letter:uppercase">{backup.progress ?? "starting"}</p>
        </div>
      </div>
    );
  }

  const failed = backup.status === "failed";

  return (
    <div className="flex items-center gap-3 px-4 py-3">
      {failed
        ? <AlertCircle size={16} className="shrink-0 text-negative" />
        : <Archive size={16} className="shrink-0 text-muted-foreground" />}
      <div className="min-w-0 flex-1">
        {failed ? (
          <>
            <p className="text-sm font-medium">Backup failed</p>
            <p className="text-xs text-negative">{backup.error ?? "The backup did not finish."}</p>
          </>
        ) : (
          <>
            <p className="truncate font-mono text-sm" title={backup.sha256 ? `sha256 ${backup.sha256}` : undefined}>
              {backup.filename}
            </p>
            <p className="text-xs text-muted-foreground">
              {formatDateTime(backup.created_at)} · {formatBytes(backup.bytes)}
              {backup.requested_by && ` · ${backup.requested_by}`}
            </p>
          </>
        )}
      </div>
      <div className="flex shrink-0 items-center gap-1">
        {!failed && (
          <Button variant="outline" size="sm" onClick={onDownload} disabled={downloading} className="gap-1.5">
            <Download size={13} />
            Download
          </Button>
        )}
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={onRemove}
          title="Delete"
          aria-label="Delete backup"
          className="text-destructive hover:bg-destructive/10 hover:text-destructive"
        >
          <Trash2 size={13} />
        </Button>
      </div>
    </div>
  );
}

// ── Instance keys ─────────────────────────────────────────────────────────────

/** The .env a new instance needs before it can read this one's backups. */
function keysFile(revealed: BackupKeys["keys"], host: string): string {
  return [
    `# Fin instance keys, exported from ${host} on ${new Date().toISOString().slice(0, 10)}.`,
    "# A backup of that instance only restores into a Fin started with these values.",
    "# Keep this file apart from the backup: together they expose every saved credential.",
    ...revealed.map((k) => `${k.name}=${k.value}`),
    "",
  ].join("\n");
}

function InstanceKeys({ overview }: { overview: BackupOverview }) {
  const confirm = useConfirm();
  // Held in component state, never the query cache: the values should not
  // outlive this panel being open.
  const [revealed, setRevealed] = useState<BackupKeys["keys"] | null>(null);
  const [copied, setCopied] = useState<string | null>(null);

  const reveal = useMutation({
    mutationFn: () => api.post<BackupKeys>("/backups/keys"),
    onSuccess: (data) => setRevealed(data.keys),
  });

  function copy(name: string, value: string) {
    navigator.clipboard.writeText(value);
    setCopied(name);
    setTimeout(() => setCopied(null), 2000);
  }

  const description =
    "Saved credentials for Plaid, Coinbase and the other integrations are encrypted with keys that live on this " +
    "server, not in the backup. A new instance can only restore a backup if it is started with the same keys.";

  if (overview.keys.length === 0) {
    return (
      <SettingsSubsection label="Instance keys" description={description}>
        <p className="rounded-lg border px-4 py-3 text-sm text-muted-foreground">
          This instance has no keys set in its environment, so a backup of it restores anywhere.
        </p>
      </SettingsSubsection>
    );
  }

  return (
    <SettingsSubsection label="Instance keys" description={description}>
      <div className="divide-y rounded-lg border">
        {overview.keys.map((key) => {
          const value = revealed?.find((k) => k.name === key.name)?.value;
          return (
            <div key={key.name} className="flex items-center gap-3 px-4 py-2.5">
              <KeyRound size={14} className="shrink-0 text-muted-foreground" />
              <div className="min-w-0 flex-1">
                <p className="truncate font-mono text-xs">{key.name}</p>
                {value !== undefined && (
                  <p className="truncate font-mono text-xs text-muted-foreground select-all">{value}</p>
                )}
              </div>
              {value !== undefined && (
                <Button variant="outline" size="xs" onClick={() => copy(key.name, value)} aria-label={`Copy ${key.name}`} className="shrink-0 gap-1.5">
                  {copied === key.name ? <Check size={12} className="text-positive" /> : <Copy size={12} />}
                  {copied === key.name ? "Copied" : "Copy"}
                </Button>
              )}
            </div>
          );
        })}
      </div>
      {revealed ? (
        <div className="flex gap-2">
          <Button variant="ghost" size="sm" onClick={() => setRevealed(null)}>Hide keys</Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => downloadText(`fin-keys-${overview.address.host}.env`, keysFile(revealed, overview.address.host))}
            className="gap-1.5"
          >
            <Download size={13} />
            Download as .env
          </Button>
        </div>
      ) : (
        <Button
          variant="outline"
          size="sm"
          disabled={reveal.isPending}
          onClick={async () => {
            if (await confirm({
              title: "Reveal the instance keys?",
              description: "Together with a backup, these keys expose every saved credential. Revealing them is recorded in the activity log.",
              confirmLabel: "Reveal",
            })) reveal.mutate();
          }}
          className="gap-1.5"
        >
          <KeyRound size={13} />
          Reveal keys
        </Button>
      )}
    </SettingsSubsection>
  );
}

// ── Moving to a new address ───────────────────────────────────────────────────

function MoveLinks({ host, meUserId }: { host: string; meUserId: string }) {
  const { data: members = [], isLoading, isError, refetch } = useQuery(queries.householdMembers());
  const [address, setAddress] = useState("");
  const [links, setLinks] = useState<Record<string, DeviceInvite>>({});
  const [error, setError] = useState("");

  const issue = useMutation({
    mutationFn: (member: HouseholdMember) =>
      api.post<DeviceInvite>("/device_invites", { address: address.trim(), user_id: member.user.id }),
    onSuccess: (link, member) => { setLinks((prev) => ({ ...prev, [member.user.id]: link })); setError(""); },
    onError: (err: Error) => setError(err.message),
  });

  return (
    <SettingsSubsection
      label="Moving to a new address"
      description={
        <>
          Passkeys only work at the address they were registered on, which for this instance
          is <span className="font-mono text-foreground">{host}</span>. Restored anywhere else, nobody's passkey will sign in.
          Before you move, create a sign-in link for each member: opened at the new address, it registers a new passkey.
        </>
      }
    >
      <div className="space-y-1.5">
        <Label htmlFor="backup-new-address">New address</Label>
        <Input
          id="backup-new-address"
          placeholder="fin.example.com"
          value={address}
          // A link is bound to the address it was made for; changing the
          // address makes the ones on screen wrong, so they go.
          onChange={(e) => { setAddress(e.target.value); setLinks({}); setError(""); }}
          autoComplete="off"
          className="max-w-sm"
        />
        <FieldError>{error}</FieldError>
      </div>

      {isLoading ? (
        <SkeletonList rows={2} rowClassName="h-12 rounded-lg" className="space-y-2" />
      ) : isError ? (
        <ErrorState title="Failed to load members" onRetry={() => refetch()} />
      ) : (
        <div className="divide-y rounded-lg border">
          {members.map((member) => (
            <MoveLinkRow
              key={member.id}
              member={member}
              isMe={member.user.id === meUserId}
              link={links[member.user.id]}
              disabled={!address.trim() || issue.isPending}
              onCreate={() => issue.mutate(member)}
            />
          ))}
        </div>
      )}
    </SettingsSubsection>
  );
}

function MoveLinkRow({ member, isMe, link, disabled, onCreate }: {
  member: HouseholdMember;
  isMe: boolean;
  link?: DeviceInvite;
  disabled: boolean;
  onCreate: () => void;
}) {
  const [copied, setCopied] = useState(false);

  function copy(url: string) {
    navigator.clipboard.writeText(url);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className="space-y-2 px-4 py-3">
      <div className="flex items-center gap-3">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium">
            {member.user.name ?? member.user.email}
            {isMe && <span className="font-normal text-muted-foreground"> (you)</span>}
          </p>
          {member.user.name && <p className="truncate text-xs text-muted-foreground">{member.user.email}</p>}
        </div>
        {!link && (
          <Button variant="outline" size="sm" onClick={onCreate} disabled={disabled} aria-label={`Create link for ${member.user.email}`} className="shrink-0 gap-1.5">
            <Link2 size={13} />
            Create link
          </Button>
        )}
      </div>
      {link?.url && (
        <>
          <div className="flex items-center gap-2">
            <code className="flex-1 truncate rounded-md bg-muted px-3 py-2 font-mono text-xs">{link.url}</code>
            <Button variant="outline" size="sm" onClick={() => copy(link.url!)} aria-label={`Copy link for ${member.user.email}`} className="shrink-0 gap-1.5">
              {copied ? <Check size={12} className="text-positive" /> : <Copy size={12} />}
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            Works once, only at {link.host}, until {formatDateTime(link.expires_at)}. It won't be shown again.
          </p>
        </>
      )}
    </div>
  );
}

// ── Restoring ─────────────────────────────────────────────────────────────────

function RestoreSteps() {
  return (
    <SettingsSubsection label="Restoring a backup">
      <ol className="list-decimal space-y-2 pl-5 text-sm text-muted-foreground marker:text-muted-foreground/60">
        <li>
          Set up a fresh Fin with the instance keys above in its environment. On Fog, attach the backup
          under <span className="text-foreground">Migrating from another instance?</span> while installing; it asks for the keys there.
        </li>
        <li>
          Anywhere else, open the new instance before anyone registers and
          choose <span className="text-foreground">Restore from a backup instead</span>.
        </li>
        <li>
          If the address changed, confirm the move when asked, then open your sign-in link there. Settings → Issues
          lists anything still pointing at the old address.
        </li>
      </ol>
    </SettingsSubsection>
  );
}
