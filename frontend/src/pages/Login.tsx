import { useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Fingerprint, ChevronLeft } from "lucide-react";
import { FinMark } from "@/components/FinMark";
import { usePasskeyLogin } from "@/hooks/usePasskeyLogin";
import { fetchSetupStatus, fogSigninUrl, type SetupStatus } from "@/api/auth";
import { safePath, signinErrorMessage } from "@/lib/signin";

interface Props {
  onLogin: (token: string) => void;
}

export function Login({ onLogin }: Props) {
  const [email, setEmail] = useState("");
  // A page that needs a session first (fog's consent page) sends people
  // here with where to go back to in the fragment; home otherwise.
  const location = useLocation();
  const [hash] = useState(() => new URLSearchParams(location.hash.slice(1)));
  const returnTo = safePath(hash.get("return_to"));
  const { signIn, busy, error } = usePasskeyLogin({
    login: onLogin,
    onNoPasskey: () => "No passkey for this device. Try registering one.",
    returnTo,
  });
  // How people sign in here: Fin's passkeys, fog alongside them, or — once
  // Fin has proven it runs on fog — fog alone.
  const [signin, setSignin] = useState<SetupStatus["signin"] | null>(null);
  useEffect(() => {
    fetchSetupStatus()
      .then((status) => setSignin(status?.signin ?? null))
      .catch(() => setSignin(null));
  }, []);
  const fogSignin = signin?.enabled === true;
  const fogOnly = signin?.fog_only === true;
  // A fog sign-in that came back refused or broken says why (the callback
  // leaves the reason in the fragment).
  const [signinError] = useState(() => signinErrorMessage(hash.get("signin_error")));

  const handleSignIn = () => signIn(email.trim() || undefined);

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
      <div className="w-full max-w-sm space-y-6 rounded-2xl border bg-card p-8 shadow-sm">
        <Link to="/" className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground">
          <ChevronLeft size={14} />
          Back
        </Link>

        <div className="space-y-1 text-center">
          <FinMark className="mx-auto mb-3 size-12" />
          <h1 className="text-2xl font-semibold tracking-tight">Welcome back</h1>
          <p className="text-sm text-muted-foreground">
            {fogOnly ? "Fin signs everyone in with fog." : "Sign in with the passkey on this device."}
          </p>
        </div>

        {(fogSignin || signinError) && (
          <div className="space-y-3">
            {fogSignin && (
              <Button className="w-full" onClick={() => window.location.assign(fogSigninUrl(returnTo))}>
                Sign in with fog
              </Button>
            )}
            {signinError && (
              <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{signinError}</p>
            )}
            {fogSignin && !fogOnly && <p className="text-center text-xs text-muted-foreground">or</p>}
          </div>
        )}

        {!fogOnly && (
          <>
            <div className="space-y-3">
              <div className="space-y-1.5">
                <Label htmlFor="email">
                  Email <span className="text-muted-foreground/60">(optional — speeds up the picker)</span>
                </Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  autoComplete="username webauthn"
                />
              </div>

              {error && <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</p>}

              <Button variant={fogSignin ? "outline" : "default"} className="w-full gap-2" onClick={handleSignIn} disabled={busy}>
                <Fingerprint size={16} />
                {busy ? "Waiting for passkey…" : "Sign in with passkey"}
              </Button>
            </div>

            <p className="text-center text-xs text-muted-foreground">
              New here? <Link to="/register" className="font-medium text-foreground hover:underline">Create an account</Link>
            </p>
          </>
        )}
      </div>
    </div>
  );
}
