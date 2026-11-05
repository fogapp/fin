import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { loginWithPasskey } from "@/api/auth";

/**
 * The passkey sign-in flow shared by Landing and Login: busy/error state,
 * the WebAuthn ceremony, storing the session token, and the redirect home.
 *
 * WebAuthn reports "no credential available" via `.name === "NotAllowedError"`
 * — the `.message` is a browser-localized string and shouldn't be compared
 * against a constant. `onNoPasskey` decides what that case means for the page:
 * return a message to show inline (Login), or navigate away and return
 * nothing (Landing falls back to the email-hint form).
 */
export function usePasskeyLogin({ login, onNoPasskey, returnTo = "/" }: {
  login: (token: string) => void;
  onNoPasskey: () => string | void;
  /** Where to land once signed in (a path on this host); home by default. */
  returnTo?: string;
}) {
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function signIn(email?: string) {
    setError("");
    setBusy(true);
    try {
      const session = await loginWithPasskey({ email });
      login(session.token);
      navigate(returnTo, { replace: true });
    } catch (e) {
      if ((e as { name?: string })?.name === "NotAllowedError") {
        const message = onNoPasskey();
        if (message) setError(message);
      } else {
        setError((e as Error).message || "Sign-in failed");
      }
    } finally {
      setBusy(false);
    }
  }

  return { signIn, busy, error };
}
