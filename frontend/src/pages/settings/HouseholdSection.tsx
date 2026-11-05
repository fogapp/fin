import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Copy, Trash2, UserPlus, LogOut, Plus, ShieldCheck, AlertTriangle, Users } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { useAuth } from "@/hooks/useAuth";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { FieldError } from "@/components/ui/field";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/empty-state";
import { useConfirm } from "@/components/ui/confirm";
import { Dialog, DialogContent, DialogHeader, DialogFooter } from "@/components/ui/dialog";
import { ErrorState } from "@/components/PageState";
import { formatDate } from "@/lib/utils";
import { SkeletonList } from "@/components/ui/skeleton";
import type { Household, HouseholdMember, HouseholdInvite, InviteCreated, Me } from "@/api/types";
import { invalidate, keys } from "@/api/keys";
import { TimeZoneCard } from "@/pages/settings/TimeZoneCard";

export function HouseholdSection() {
  const { data: me } = useQuery(queries.me());
  const { data: households = [] } = useQuery(queries.households());

  const isAdmin = me?.household.role === "admin";

  return (
    <div className="space-y-6">
      <GeneralCard me={me} households={households} isAdmin={isAdmin} />
      <TimeZoneCard isAdmin={isAdmin} />
      <MembersCard isAdmin={isAdmin} meUserId={me?.user.id} />
      {isAdmin && <InvitesCard />}
      <CreateHouseholdCard />
      {isAdmin && me && <DeleteHouseholdCard me={me} householdCount={households.length} />}
    </div>
  );
}

// ── General ───────────────────────────────────────────────────────────────────

function GeneralCard({ me, households, isAdmin }: { me?: Me; households: Household[]; isAdmin: boolean }) {
  const qc = useQueryClient();
  const [name, setName] = useState("");
  const [editing, setEditing] = useState(false);

  const rename = useMutation({
    mutationFn: (newName: string) => api.patch(`/households/${me?.household.id}`, { name: newName }),
    onSuccess: () => {
      invalidate(qc, keys.me, keys.households);
      setEditing(false);
    },
  });

  if (!me) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-base font-semibold text-foreground">Active household</CardTitle>
        </CardHeader>
        <CardContent>
          <SkeletonList rows={3} />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-semibold text-foreground">Active household</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <Row label="Name">
          {editing ? (
            <form
              onSubmit={(e) => { e.preventDefault(); rename.mutate(name.trim()); }}
              className="flex items-center gap-2"
            >
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                autoFocus
                aria-label="Household name"
                className="h-8 max-w-xs"
              />
              <Button size="sm" variant="ghost" type="button" onClick={() => setEditing(false)}>Cancel</Button>
              <Button size="sm" type="submit" disabled={!name.trim() || rename.isPending}>
                {rename.isPending ? "Saving…" : "Save"}
              </Button>
            </form>
          ) : (
            <div className="flex items-center gap-3">
              <span className="font-medium">{me.household.name}</span>
              {isAdmin && (
                <Button size="sm" variant="ghost" onClick={() => { setName(me.household.name); setEditing(true); }}>
                  Rename
                </Button>
              )}
            </div>
          )}
        </Row>
        <Row label="Your role"><RoleBadge role={me.household.role ?? "member"} /></Row>
        <Row label="Members in this household">{households.find((h) => h.active)?.role ?? "—"} you, and others →</Row>
      </CardContent>
    </Card>
  );
}

// ── Members ───────────────────────────────────────────────────────────────────

function MembersCard({ isAdmin, meUserId }: { isAdmin: boolean; meUserId: string | undefined }) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const { data: members = [], isLoading, isError, refetch } = useQuery(queries.householdMembers());

  const updateRole = useMutation({
    mutationFn: ({ id, role }: { id: string; role: "admin" | "member" }) =>
      api.patch(`/household_memberships/${id}`, { role }),
    onSuccess: () => invalidate(qc, keys.householdMembers),
  });

  const remove = useMutation({
    mutationFn: (id: string) => api.delete(`/household_memberships/${id}`),
    onSuccess: () => invalidate(qc, keys.householdMembers),
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-semibold text-foreground">Members</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading && <SkeletonList rows={2} />}
        {isError && <ErrorState title="Failed to load members" onRetry={() => refetch()} />}
        {!isLoading && !isError && members.length === 0 && (
          <EmptyState
            icon={Users}
            title="No other members yet."
            description="Share an invite below to add someone."
            className="py-6"
          />
        )}
        {!isError && members.length > 0 && (
        <div className="divide-y rounded-lg border">
          {members.map((m) => (
            <MemberRow
              key={m.id}
              member={m}
              isMe={m.user.id === meUserId}
              isAdmin={isAdmin}
              onChangeRole={(role) => updateRole.mutate({ id: m.id, role })}
              onRemove={async () => {
                const isMe = m.user.id === meUserId;
                const ok = await confirm({
                  title: isMe ? "Leave household?" : `Remove ${m.user.email}?`,
                  confirmLabel: isMe ? "Leave" : "Remove",
                  destructive: true,
                });
                if (ok) remove.mutate(m.id);
              }}
            />
          ))}
        </div>
        )}
      </CardContent>
    </Card>
  );
}

function MemberRow({ member, isMe, isAdmin, onChangeRole, onRemove }: {
  member: HouseholdMember;
  isMe: boolean;
  isAdmin: boolean;
  onChangeRole: (role: "admin" | "member") => void;
  onRemove: () => void;
}) {
  return (
    <div className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
      <div className="min-w-0">
        <p className="truncate font-medium">{member.user.name || member.user.email}</p>
        <p className="truncate text-xs text-muted-foreground">{member.user.email}</p>
      </div>
      <div className="flex items-center gap-2">
        {isAdmin && !isMe ? (
          <Select
            value={member.role}
            onChange={(e) => onChangeRole(e.target.value as "admin" | "member")}
            aria-label={`Role for ${member.user.email}`}
            wrapperClassName="w-28"
            className="h-7 pl-2 text-xs"
          >
            <option value="member">member</option>
            <option value="admin">admin</option>
          </Select>
        ) : (
          <RoleBadge role={member.role} />
        )}
        {(isAdmin || isMe) && (
          <Button
            size="icon-sm"
            variant="ghost"
            onClick={onRemove}
            title={isMe ? "Leave household" : "Remove"}
            aria-label={isMe ? "Leave household" : "Remove member"}
            className="text-destructive hover:bg-destructive/10 hover:text-destructive"
          >
            {isMe ? <LogOut size={14} /> : <Trash2 size={14} />}
          </Button>
        )}
      </div>
    </div>
  );
}

// ── Invites ───────────────────────────────────────────────────────────────────

function InvitesCard() {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const { data: invites = [], isLoading, isError, refetch } = useQuery(queries.householdInvites());

  const [role, setRole] = useState<"admin" | "member">("member");
  const [days, setDays] = useState(7);

  const create = useMutation({
    mutationFn: () => api.post<InviteCreated>("/invites", { role, expires_in_days: days }),
    onSuccess: () => invalidate(qc, keys.invites),
  });

  const revoke = useMutation({
    mutationFn: (code: string) => api.delete(`/invites/${code}`),
    onSuccess: () => invalidate(qc, keys.invites),
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-semibold text-foreground">Invites</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <form
          onSubmit={(e) => { e.preventDefault(); create.mutate(); }}
          className="flex flex-wrap items-end gap-3"
        >
          <div className="space-y-1">
            <Label htmlFor="invite-role">Role</Label>
            <Select
              id="invite-role"
              value={role}
              onChange={(e) => setRole(e.target.value as "admin" | "member")}
              wrapperClassName="w-32"
            >
              <option value="member">member</option>
              <option value="admin">admin</option>
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor="invite-days">Expires in (days)</Label>
            <Input
              id="invite-days"
              type="number"
              min={1}
              max={90}
              value={days}
              onChange={(e) => setDays(Number(e.target.value))}
              className="h-9 w-24 tabular-nums"
            />
          </div>
          <Button type="submit" size="sm" disabled={create.isPending} className="gap-1.5">
            <UserPlus size={14} />
            {create.isPending ? "Creating…" : "Create invite"}
          </Button>
        </form>

        {isLoading && <SkeletonList rows={2} />}
        {isError && <ErrorState title="Failed to load invites" onRetry={() => refetch()} />}
        {!isLoading && !isError && invites.length === 0 && (
          <EmptyState title="No active invites." className="py-6" />
        )}
        {invites.length > 0 && (
          <div className="divide-y rounded-lg border">
            {invites.map((inv) => (
              <InviteRow key={inv.code} invite={inv} onRevoke={async () => {
                if (await confirm({ title: "Revoke this invite?", confirmLabel: "Revoke", destructive: true })) {
                  revoke.mutate(inv.code);
                }
              }} />
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function InviteRow({ invite, onRevoke }: { invite: HouseholdInvite; onRevoke: () => void }) {
  const acceptUrl = `${window.location.origin}/register?invite=${invite.code}`;
  return (
    <div className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{invite.code}</code>
          <RoleBadge role={invite.role} />
        </div>
        <p className="mt-1 truncate text-xs text-muted-foreground">
          {invite.expires_at ? `Expires ${formatDate(invite.expires_at)}` : "No expiration"}
        </p>
      </div>
      <div className="flex items-center gap-1">
        <Button
          size="icon-sm"
          variant="ghost"
          onClick={() => navigator.clipboard.writeText(acceptUrl)}
          title="Copy invite link"
          aria-label="Copy invite link"
        >
          <Copy size={14} />
        </Button>
        <Button
          size="icon-sm"
          variant="ghost"
          onClick={onRevoke}
          title="Revoke"
          aria-label="Revoke invite"
          className="text-destructive hover:bg-destructive/10 hover:text-destructive"
        >
          <Trash2 size={14} />
        </Button>
      </div>
    </div>
  );
}

// ── Create new household ──────────────────────────────────────────────────────

function CreateHouseholdCard() {
  const qc = useQueryClient();
  const [name, setName] = useState("");

  const create = useMutation({
    mutationFn: () => api.post<Household>("/households", { name: name.trim() }),
    onSuccess: () => {
      invalidate(qc, keys.households);
      setName("");
    },
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-semibold text-foreground">Create another household</CardTitle>
      </CardHeader>
      <CardContent>
        <form
          onSubmit={(e) => { e.preventDefault(); if (name.trim()) create.mutate(); }}
          className="flex flex-wrap items-end gap-3"
        >
          <div className="flex-1 min-w-[200px] space-y-1">
            <Label htmlFor="new-household-name">Name</Label>
            <Input
              id="new-household-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Vacation Fund"
              className="h-9"
            />
          </div>
          <Button type="submit" size="sm" disabled={!name.trim() || create.isPending} className="gap-1.5">
            <Plus size={14} />
            {create.isPending ? "Creating…" : "Create"}
          </Button>
        </form>
        <p className="mt-2 text-xs text-muted-foreground">
          You'll be admin of the new household. Switch to it from the header dropdown.
        </p>
      </CardContent>
    </Card>
  );
}

// ── Danger zone: delete household ─────────────────────────────────────────────

interface DeleteSessionResponse {
  token: string;
  household: { id: string; name: string; role: string };
}

function DeleteHouseholdCard({ me, householdCount }: { me: Me; householdCount: number }) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { login } = useAuth();

  const [open, setOpen] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [error, setError] = useState("");
  const targetName = me.household.name;
  const isOnlyHousehold = householdCount < 2;

  const destroy = useMutation({
    mutationFn: () => api.delete<DeleteSessionResponse>(`/households/${me.household.id}`),
    onSuccess: (res) => {
      // The old token was on the deleted household and is gone via FK
      // cascade — the backend already minted us a new one on a remaining
      // household. Swap it in and drop every cached query.
      login(res.token);
      qc.clear();
      navigate("/", { replace: true });
    },
    onError: (err: Error) => setError(err.message),
  });

  return (
    <Card className="border-destructive/40">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base font-semibold text-destructive">
          <AlertTriangle size={16} />
          Delete this household
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Permanently removes <strong className="text-foreground">{targetName}</strong> and
          every account, transaction, broker, category, rule, and invite scoped to it.
          Other members lose access. This cannot be undone.
        </p>

        {isOnlyHousehold ? (
          <p className="rounded-lg border border-input bg-muted/40 p-3 text-xs text-muted-foreground">
            You can't delete your only household. Create or accept an invite to another one first.
          </p>
        ) : (
          <>
            <Button
              variant="destructive"
              onClick={() => { setError(""); setConfirmText(""); setOpen(true); }}
              className="gap-1.5"
            >
              <Trash2 size={14} />
              Delete household…
            </Button>

            <Dialog open={open} onOpenChange={setOpen}>
              <DialogContent size="sm">
                <DialogHeader title={`Delete ${targetName}?`} />
                <div className="space-y-3 px-5 py-4">
                  <p className="text-sm text-muted-foreground">
                    This permanently deletes the household and everything scoped to it.
                    It cannot be undone.
                  </p>
                  <div className="space-y-1.5">
                    <Label htmlFor="delete-household-confirm">
                      Type <code className="rounded bg-muted px-1 py-0.5 font-mono">{targetName}</code> to confirm
                    </Label>
                    <Input
                      id="delete-household-confirm"
                      autoFocus
                      value={confirmText}
                      onChange={(e) => setConfirmText(e.target.value)}
                      placeholder={targetName}
                    />
                    <FieldError>{error || null}</FieldError>
                  </div>
                </div>
                <DialogFooter>
                  <Button variant="outline" size="sm" onClick={() => setOpen(false)}>Cancel</Button>
                  <Button
                    variant="destructive"
                    size="sm"
                    disabled={confirmText.trim() !== targetName || destroy.isPending}
                    onClick={() => { setError(""); destroy.mutate(); }}
                  >
                    {destroy.isPending ? "Deleting…" : `Delete ${targetName}`}
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </>
        )}
      </CardContent>
    </Card>
  );
}

// ── Bits ──────────────────────────────────────────────────────────────────────

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span className="text-sm">{children}</span>
    </div>
  );
}

function RoleBadge({ role }: { role: "admin" | "member" }) {
  return role === "admin" ? (
    <Badge variant="outline" className="gap-1"><ShieldCheck size={11} />admin</Badge>
  ) : (
    <Badge variant="outline">member</Badge>
  );
}
