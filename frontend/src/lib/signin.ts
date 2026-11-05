/** Only a path on this host: a sign-in's return path rides in a URL
 *  fragment, which is the browser's to tamper with. */
export function safePath(raw: string | null | undefined): string {
  return raw && raw.startsWith("/") && !raw.startsWith("//") && !raw.includes("\\") ? raw : "/";
}

/** Why a fog sign-in did not finish, in words for the login page: the
 *  callback leaves the reason in the fragment (#signin_error=…). */
export function signinErrorMessage(code: string | null): string | null {
  switch (code) {
    case null:
    case "":
      return null;
    case "access_denied":
      return "fog didn't let you in. Ask whoever runs it to share Fin with you.";
    case "passkey_required":
      return "Fin needs you to sign in to fog with a passkey.";
    case "no_household":
      return "Your Fin account isn't in a household any more. Ask a household admin to invite you back.";
    default:
      return "Signing in with fog didn't work. Try again.";
  }
}
