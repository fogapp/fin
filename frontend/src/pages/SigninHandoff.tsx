import { useEffect, useRef, useState, type ReactNode } from "react";
import { useLocation } from "react-router-dom";
import { Fingerprint, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { FinMark } from "@/components/FinMark";
import { setToken } from "@/api/client";
import { completeSigninLink, fogSigninUrl, proveAccountWithPasskey, redeemHandoff } from "@/api/auth";
import { safePath } from "@/lib/signin";

/** The fragment the sign-in callback left, read once. The real address bar
 *  is cleared at once so the one-time code never lingers in history. */
function useFragmentOnce(): URLSearchParams {
  const location = useLocation();
  const [params] = useState(() => new URLSearchParams(location.hash.slice(1)));
  useEffect(() => {
    if (window.location.hash) {
      window.history.replaceState(window.history.state, "", window.location.pathname + window.location.search);
    }
  }, []);
  return params;
}

/** Signed in: keep the token and load the app where the person was headed.
 *  A full load, so the app starts signed in at that page whichever route
 *  tree this one was rendered in. */
function enter(token: string, to: string | null | undefined) {
  setToken(token);
  window.location.assign(safePath(to));
}

/** /auth/complete — fog (or a console recovery link) sent the person back
 *  signed in; trade the one-time code for the session token, as a passkey
 *  sign-in would have answered. */
export function SigninComplete() {
  const params = useFragmentOnce();
  const handoff = params.get("handoff");
  const [error, setError] = useState<string | null>(handoff ? null : "This sign-in link is incomplete. Sign in again.");
  const started = useRef(false);

  useEffect(() => {
    if (!handoff || started.current) return;
    started.current = true;
    redeemHandoff(handoff)
      .then((session) => enter(session.token, params.get("return_to")))
      .catch((e) => setError((e as Error).message || "This sign-in link has expired. Sign in again."));
  }, [handoff, params]);

  return (
    <SigninCard>
      {error ? (
        <>
          <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</p>
          <Button className="w-full" onClick={() => window.location.assign("/login")}>Back to sign-in</Button>
        </>
      ) : (
        <p className="flex items-center justify-center gap-2 text-sm text-muted-foreground">
          <Loader2 size={16} className="animate-spin" />
          Signing you in…
        </p>
      )}
    </SigninCard>
  );
}

/** /auth/link — fog says who this is, but Fin already has accounts and
 *  none is connected to this fog sign-in. Never guessed by email: the person
 *  proves an account is theirs by signing in to it with its Fin passkey,
 *  once, or starts a fresh one. */
export function SigninLink() {
  const params = useFragmentOnce();
  const pending = params.get("pending") ?? "";
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function connect(fresh: boolean) {
    setError(null);
    setBusy(true);
    try {
      const proof = fresh ? undefined : await proveAccountWithPasskey({ pending, email: email.trim() || undefined });
      const { session, returnTo } = await completeSigninLink({ pending, proof, fresh });
      enter(session.token, returnTo);
    } catch (e) {
      setError(
        (e as { name?: string })?.name === "NotAllowedError"
          ? "No Fin passkey on this device. Try another device, or start fresh."
          : (e as Error).message || "That didn't work. Sign in with fog again.",
      );
      setBusy(false);
    }
  }

  if (!pending) {
    return (
      <SigninCard>
        <p className="text-sm text-muted-foreground">This sign-in has nothing to connect. Sign in with fog again.</p>
        <Button className="w-full" onClick={() => window.location.assign(fogSigninUrl())}>Sign in with fog</Button>
      </SigninCard>
    );
  }

  return (
    <SigninCard>
      <div className="space-y-1 text-center">
        <h1 className="text-xl font-semibold tracking-tight">Connect your Fin account</h1>
        <p className="text-sm text-muted-foreground">
          fog signed you in, and Fin already has accounts. Sign in to yours with its Fin passkey once to
          connect it — from then on fog signs you in.
        </p>
      </div>

      <div className="space-y-3">
        <div className="space-y-1.5">
          <Label htmlFor="link-email">
            Email <span className="text-muted-foreground/60">(optional — speeds up the picker)</span>
          </Label>
          <Input
            id="link-email"
            type="email"
            placeholder="you@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="username webauthn"
          />
        </div>

        {error && <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</p>}

        <Button className="w-full gap-2" onClick={() => void connect(false)} disabled={busy}>
          <Fingerprint size={16} />
          {busy ? "Working…" : "Sign in with your Fin passkey to connect it"}
        </Button>
        <Button variant="outline" className="w-full" onClick={() => void connect(true)} disabled={busy}>
          I don't have one — start fresh
        </Button>
      </div>
    </SigninCard>
  );
}

function SigninCard({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
      <div className="w-full max-w-sm space-y-6 rounded-2xl border bg-card p-8 shadow-sm">
        <FinMark className="mx-auto size-12" />
        {children}
      </div>
    </div>
  );
}
