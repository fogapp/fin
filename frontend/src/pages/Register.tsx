import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Fingerprint, ChevronLeft, ArchiveRestore } from "lucide-react";
import { registerPasskey, fetchInvitePreview, fogSigninUrl, type InvitePreview, type SetupStatus } from "@/api/auth";
import { FinMark } from "@/components/FinMark";
import { api } from "@/api/client";

interface Props {
  onLogin: (token: string) => void;
}

export function Register({ onLogin }: Props) {
  const navigate = useNavigate();
  const [search] = useSearchParams();
  const inviteCode = search.get("invite") || "";

  const [email, setEmail] = useState("");
  const [name, setName]   = useState("");
  const [invite, setInvite] = useState<InvitePreview | null>(null);
  const [inviteErr, setInviteErr] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy]   = useState(false);

  // Without an invite code, clear any previously-fetched preview so the
  // UI doesn't keep showing a stale "Joining {household X}" header
  // (adjust-state-during-render pattern instead of setState in an effect).
  const [prevInviteCode, setPrevInviteCode] = useState(inviteCode);
  if (prevInviteCode !== inviteCode) {
    setPrevInviteCode(inviteCode);
    if (!inviteCode) {
      setInvite(null);
      setInviteErr("");
    }
  }

  useEffect(() => {
    if (!inviteCode) return;
    fetchInvitePreview(inviteCode)
      .then(setInvite)
      .catch((e) => setInviteErr((e as Error).message));
  }, [inviteCode]);

  // Fresh-instance restore door (fog-backup): only offered while no users
  // exist — the same window in which open registration is available.
  const [freshInstance, setFreshInstance] = useState(false);
  const [restoreOpen, setRestoreOpen] = useState(false);
  const [confirmIdentity, setConfirmIdentity] = useState(false);
  const [needsIdentityConfirm, setNeedsIdentityConfirm] = useState(false);
  const [restarting, setRestarting] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  // Once Fin signs everyone in with fog, its own registration is closed:
  // fog's first sign-in is the setup, and fog adds everyone after.
  const [fogOnly, setFogOnly] = useState(false);

  useEffect(() => {
    api.get<SetupStatus>("/setup")
      .then((res) => {
        setFreshInstance(res.setup_required);
        setFogOnly(res.signin?.fog_only === true);
      })
      .catch(() => setFreshInstance(false));
  }, []);

  // After the restore is armed the app restarts itself; poll until it's back
  // and recovered, then reload into the restored instance.
  useEffect(() => {
    if (!restarting) return;
    const timer = setInterval(async () => {
      try {
        const status = await api.get<SetupStatus>("/setup");
        if (!status.setup_required) window.location.replace("/login");
      } catch {
        // Still restarting/restoring — keep waiting.
      }
    }, 5000);
    return () => clearInterval(timer);
  }, [restarting]);

  async function handleRestore() {
    const file = fileRef.current?.files?.[0];
    if (!file) {
      setError("Choose a backup artifact (.fogpack.tar) first");
      return;
    }
    setError("");
    setBusy(true);
    try {
      const form = new FormData();
      form.append("artifact", file);
      if (confirmIdentity) form.append("confirm_identity", "true");
      await api.upload("/setup/restore", form);
      setRestarting(true);
    } catch (e) {
      const message = (e as Error).message || "Restore failed";
      // The preflight's identity refusal is written for operators (env names,
      // API flags); here the answer is the checkbox, so say that instead.
      if (message.includes("confirm_identity")) {
        setNeedsIdentityConfirm(true);
        setError("This backup was made at a different address. Confirm below to restore it here.");
      } else {
        setError(message);
      }
    } finally {
      setBusy(false);
    }
  }

  async function handleRegister() {
    setError("");
    setBusy(true);
    try {
      const session = await registerPasskey({
        email: email.trim(),
        name:  name.trim() || undefined,
        inviteCode: inviteCode || undefined,
      });
      onLogin(session.token);
      navigate("/", { replace: true });
    } catch (e) {
      setError((e as Error).message || "Registration failed");
    } finally {
      setBusy(false);
    }
  }

  if (restarting) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
        <div className="w-full max-w-sm space-y-3 rounded-2xl border bg-card p-8 text-center shadow-sm">
          <h1 className="text-2xl font-semibold tracking-tight">Restoring…</h1>
          <p className="text-sm text-muted-foreground">
            The artifact is armed and Fin is restarting to recover. This page
            moves to sign-in when the restored instance is back.
          </p>
          {confirmIdentity && (
            <p className="text-sm text-muted-foreground">
              Passkeys from the old address won't work here. Once it's back,
              open the sign-in link you created for this address.
            </p>
          )}
        </div>
      </div>
    );
  }

  if (fogOnly) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
        <div className="w-full max-w-sm space-y-6 rounded-2xl border bg-card p-8 text-center shadow-sm">
          <FinMark className="mx-auto size-12" />
          <div className="space-y-1">
            <h1 className="text-2xl font-semibold tracking-tight">Fin signs everyone in with fog</h1>
            <p className="text-sm text-muted-foreground">
              There's no account to create here. Sign in with fog; if Fin isn't shared with you yet, fog
              lets you ask for it.
            </p>
          </div>
          <Button className="w-full" onClick={() => window.location.assign(fogSigninUrl())}>Sign in with fog</Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
      <div className="w-full max-w-sm space-y-6 rounded-2xl border bg-card p-8 shadow-sm">
        <Link to="/" className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
          <ChevronLeft size={14} />
          Back
        </Link>

        <div className="space-y-1 text-center">
          <FinMark className="mx-auto mb-3 size-12" />
          <h1 className="text-2xl font-semibold tracking-tight">Create your account</h1>
          <p className="text-sm text-muted-foreground">
            {invite
              ? <>Joining <strong>{invite.household.name}</strong> as <strong>{invite.role}</strong></>
              : "Pick an email and enroll a passkey on this device."}
          </p>
        </div>

        {inviteErr && <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{inviteErr}</p>}

        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="email" required>Email</Label>
            <Input
              id="email"
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoFocus
              autoComplete="username"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="name">Display name <span className="text-muted-foreground/60">(optional)</span></Label>
            <Input
              id="name"
              type="text"
              placeholder="Your name"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>

          {error && <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</p>}

          <Button className="w-full gap-2" onClick={handleRegister} disabled={busy || !email.trim()}>
            <Fingerprint size={16} />
            {busy ? "Setting up passkey…" : "Create passkey"}
          </Button>
        </div>

        {freshInstance && !invite && (
          <div className="space-y-3 border-t pt-4">
            <button
              type="button"
              onClick={() => setRestoreOpen((v) => !v)}
              className="inline-flex w-full items-center justify-center gap-2 text-xs font-medium text-muted-foreground hover:text-foreground"
            >
              <ArchiveRestore size={14} />
              {restoreOpen ? "Hide restore" : "Restore from a backup instead"}
            </button>
            {restoreOpen && (
              <div className="space-y-3">
                <p className="text-xs text-muted-foreground">
                  Upload a .fogpack.tar from another Fin (Settings → Backup
                  there, or Fog's Backups page). This instance has to be
                  running with that one's instance keys.
                </p>
                <input
                  ref={fileRef}
                  type="file"
                  accept=".tar,application/x-tar"
                  className="block w-full text-xs text-muted-foreground file:mr-3 file:rounded-md file:border file:bg-muted file:px-3 file:py-1.5 file:text-xs"
                />
                {needsIdentityConfirm && (
                  <label className="flex items-start gap-2 text-xs text-muted-foreground">
                    <input
                      type="checkbox"
                      checked={confirmIdentity}
                      onChange={(e) => setConfirmIdentity(e.target.checked)}
                      className="mt-0.5"
                    />
                    <span>
                      This backup comes from a different address. Restore it
                      here anyway: existing passkeys won't sign in at this
                      address, so have a sign-in link for it ready (Settings →
                      Backup on the old instance).
                    </span>
                  </label>
                )}
                <Button variant="outline" className="w-full" onClick={handleRestore} disabled={busy}>
                  {busy ? "Uploading…" : "Restore from backup"}
                </Button>
              </div>
            )}
          </div>
        )}

        <p className="text-center text-xs text-muted-foreground">
          Have an account? <Link to="/login" className="font-medium text-foreground hover:underline">Sign in</Link>
        </p>
      </div>
    </div>
  );
}
