import { useState } from "react";
import { useSearchParams, useNavigate } from "react-router-dom";
import { Fingerprint } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { registerDeviceViaInvite } from "@/api/auth";

interface Props {
  onLogin: (token: string) => void;
}

export function JoinDevice({ onLogin }: Props) {
  const [search] = useSearchParams();
  const navigate = useNavigate();
  const inviteToken = search.get("token") ?? "";

  const [nickname, setNickname] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  if (!inviteToken) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
        <div className="w-full max-w-sm rounded-2xl border bg-card p-8 text-center space-y-3">
          <p className="text-sm font-medium">Invalid link</p>
          <p className="text-sm text-muted-foreground">This device invite link is missing or malformed.</p>
        </div>
      </div>
    );
  }

  async function handleRegister() {
    setError(null);
    setBusy(true);
    try {
      const session = await registerDeviceViaInvite({
        inviteToken,
        nickname: nickname.trim() || undefined,
      });
      setDone(true);
      onLogin(session.token);
      setTimeout(() => navigate("/", { replace: true }), 800);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Registration failed");
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
        <div className="w-full max-w-sm rounded-2xl border bg-card p-8 text-center space-y-3">
          <Fingerprint size={32} className="mx-auto text-primary" />
          <p className="text-sm font-medium">Device registered — signing you in…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
      <div className="w-full max-w-sm space-y-6 rounded-2xl border bg-card p-8 shadow-sm">
        <div className="space-y-1 text-center">
          <Fingerprint size={32} className="mx-auto text-primary" />
          <h1 className="text-lg font-semibold">Register this device</h1>
          <p className="text-sm text-muted-foreground">
            Your browser will prompt you to create a passkey for this device.
          </p>
        </div>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="device-name">Device name (optional)</Label>
            <Input
              id="device-name"
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              placeholder="e.g. MacBook Pro, iPhone 15…"
              disabled={busy}
            />
          </div>

          {error && (
            <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</p>
          )}

          <Button onClick={handleRegister} disabled={busy} className="w-full">
            <Fingerprint size={15} />
            {busy ? "Follow your browser's prompt…" : "Register passkey"}
          </Button>
        </div>
      </div>
    </div>
  );
}
