import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { FinMark } from "@/components/FinMark";
import { Landmark, LineChart, ShieldCheck, GitBranch } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { usePasskeyLogin } from "@/hooks/usePasskeyLogin";
import { fetchSetupStatus, type SetupStatus } from "@/api/auth";

export function Landing() {
  const navigate = useNavigate();
  const { login } = useAuth();
  // No credential on this device → fall back to /login for an email hint.
  const { signIn, busy: signingIn, error } = usePasskeyLogin({
    login,
    onNoPasskey: () => { navigate("/login"); },
  });

  // With fog sign-in on, "Sign in" goes to /login, which offers fog; once
  // Fin signs everyone in with fog there is no account to create here.
  const [signin, setSignin] = useState<SetupStatus["signin"] | null>(null);
  useEffect(() => {
    fetchSetupStatus()
      .then((status) => setSignin(status?.signin ?? null))
      .catch(() => setSignin(null));
  }, []);
  const fogSignin = signin?.enabled === true;
  const fogOnly = signin?.fog_only === true;

  const handleSignIn = () => (fogSignin ? navigate("/login") : signIn());

  const features = [
    {
      icon: Landmark,
      title: "All your accounts in one place",
      body: "Link banks and brokerages via Plaid, or import CSVs. Cash, credit, and investments live side-by-side.",
    },
    {
      icon: LineChart,
      title: "Portfolio over time",
      body: "Position snapshots, cost basis, dividends, and a one-glance dashboard for buys, sells, and income.",
    },
    {
      icon: GitBranch,
      title: "Rules that classify automatically",
      body: "Define how transactions get tagged, categorized, and merchant-matched. Apply to history with one click.",
    },
    {
      icon: ShieldCheck,
      title: "Household-scoped, passkey-secured",
      body: "Your data lives in a household you control. Sign in with a passkey — no passwords to manage or leak.",
    },
  ];

  return (
    <div className="relative isolate min-h-screen bg-background">
      {/* Fin watermark — fixed to the viewport's bottom-right, decorative. */}
      <img
        src="/background.png"
        alt=""
        aria-hidden
        className="pointer-events-none fixed bottom-0 right-0 -z-10 w-[50vw] opacity-[0.08]"
      />

      <header className="border-b">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
          <div className="flex items-center gap-2">
            <FinMark />
            <span className="font-semibold tracking-tight">Fin</span>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={handleSignIn} disabled={signingIn}>
              {signingIn ? "Waiting for passkey…" : "Sign in"}
            </Button>
            {!fogOnly && <Button size="sm" onClick={() => navigate("/register")}>Get started</Button>}
          </div>
        </div>
      </header>

      <main>
        <section className="mx-auto max-w-3xl px-6 pb-16 pt-24 text-center">
          <h1 className="text-5xl font-bold tracking-tight">A quiet place for your money.</h1>
          <p className="mx-auto mt-6 max-w-xl text-lg text-muted-foreground">
            Fin is a personal-finance dashboard for households who want their cash, credit, and investments
            in one self-hosted place — with rules, automations, and a clean view of the months and years.
          </p>
          <div className="mt-8 flex items-center justify-center gap-3">
            {!fogOnly && <Button size="lg" onClick={() => navigate("/register")}>Get started</Button>}
            <Button size="lg" variant="outline" onClick={handleSignIn} disabled={signingIn}>
              {signingIn ? "Waiting for passkey…" : "I have an account"}
            </Button>
          </div>
          {error && <p className="mt-4 text-sm text-destructive">{error}</p>}
        </section>

        <section className="mx-auto max-w-5xl px-6 pb-24">
          <div className="grid gap-6 sm:grid-cols-2">
            {features.map(({ icon: Icon, title, body }) => (
              <div key={title} className="rounded-xl border bg-card p-6">
                <Icon size={20} className="text-primary" />
                <p className="mt-3 font-medium">{title}</p>
                <p className="mt-1 text-sm text-muted-foreground">{body}</p>
              </div>
            ))}
          </div>
        </section>
      </main>

      <footer className="border-t">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4 text-xs text-muted-foreground">
          <span>Fin — self-hosted finance</span>
          <span>Passkey-only login. Your data, your server.</span>
        </div>
      </footer>
    </div>
  );
}
