import {
  startRegistration,
  startAuthentication,
  type PublicKeyCredentialCreationOptionsJSON,
  type PublicKeyCredentialRequestOptionsJSON,
} from "@simplewebauthn/browser";
import { api } from "@/api/client";
import type { InvitePreview, PasskeyLinkProof, Session, SetupStatus } from "@/api/types";

export type SessionResponse = Session;
export type { InvitePreview, SetupStatus };


interface BeginResponse<O> {
  options: O;
  challenge_token: string;
}

// The ceremonies run before a session exists, so every call is anonymous —
// no Authorization header, but the client's shared error unwrapping applies.
const ANON = { anonymous: true } as const;

export async function registerPasskey(args: {
  email: string;
  name?: string;
  inviteCode?: string;
  nickname?: string;
}): Promise<SessionResponse> {
  const begin = await api.post<BeginResponse<PublicKeyCredentialCreationOptionsJSON>>(
    "/auth/passkey/register/begin",
    { email: args.email, name: args.name, invite_code: args.inviteCode },
    ANON,
  );

  const credential = await startRegistration({ optionsJSON: begin.options });

  return api.post<SessionResponse>("/auth/passkey/register/finish", {
    credential,
    challenge_token: begin.challenge_token,
    nickname: args.nickname,
  }, ANON);
}

export async function loginWithPasskey(args: { email?: string } = {}): Promise<SessionResponse> {
  const begin = await api.post<BeginResponse<PublicKeyCredentialRequestOptionsJSON>>(
    "/auth/passkey/login/begin",
    { email: args.email },
    ANON,
  );

  const credential = await startAuthentication({ optionsJSON: begin.options });

  return api.post<SessionResponse>("/auth/passkey/login/finish", {
    credential,
    challenge_token: begin.challenge_token,
  }, ANON);
}

/** The fog link page's proof that the person holds an account's passkey:
 *  the same WebAuthn sign-in, but answered with a short-lived proof bound to
 *  this one pending fog sign-in instead of a session. */
export async function proveAccountWithPasskey(args: { pending: string; email?: string }): Promise<string> {
  const begin = await api.post<BeginResponse<PublicKeyCredentialRequestOptionsJSON>>(
    "/auth/passkey/link/begin",
    { pending: args.pending, email: args.email },
    ANON,
  );

  const credential = await startAuthentication({ optionsJSON: begin.options });

  const proof = await api.post<PasskeyLinkProof>("/auth/passkey/link/finish", {
    credential,
    challenge_token: begin.challenge_token,
    pending: args.pending,
  }, ANON);
  return proof.link_token;
}

/** Trade a sign-in's one-time handoff code (fog sign-in, a recovery link)
 *  for its session — the same answer a passkey sign-in gives. */
export function redeemHandoff(handoff: string): Promise<SessionResponse> {
  return api.post<SessionResponse>("/handoff", { handoff }, ANON);
}

/** What POST /auth/oidc/link answers: a handoff code for the new session. */
interface LinkResult {
  handoff?: string;
  return_to?: string;
  errors?: string[];
}

/** Why connecting an account to fog failed, in words for the person. */
export class SigninLinkError extends Error {}

/**
 * Connect a pending fog sign-in to a Fin account and sign in to it: with
 * `proof` (from proveAccountWithPasskey) to connect an existing account, or
 * `fresh` to start a new one. Answers the session and where to go next.
 * /auth/oidc/link lives outside /api/v1, so it is called directly.
 */
export async function completeSigninLink(args: { pending: string; proof?: string; fresh?: boolean }): Promise<{
  session: SessionResponse;
  returnTo: string | undefined;
}> {
  const res = await fetch("/auth/oidc/link", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      ...(args.proof ? { Authorization: `Bearer ${args.proof}` } : {}),
    },
    body: JSON.stringify(args.fresh ? { pending: args.pending, fresh: "true" } : { pending: args.pending }),
  });
  const data = (await res.json().catch(() => ({}))) as LinkResult;
  if (!res.ok || !data.handoff) {
    // 409/422 carry their own words (already connected; expired). Anything
    // else is the passkey's account not being one this sign-in may take.
    if (res.status === 409 || res.status === 422) {
      throw new SigninLinkError(data.errors?.join(" ") || "This sign-in expired. Sign in with fog again.");
    }
    throw new SigninLinkError(
      "That account can't be connected. It may already be connected to someone else's fog sign-in.",
    );
  }
  return { session: await redeemHandoff(data.handoff), returnTo: data.return_to };
}

export async function registerDeviceViaInvite(args: {
  inviteToken: string;
  nickname?: string;
}): Promise<SessionResponse> {
  const begin = await api.post<BeginResponse<PublicKeyCredentialCreationOptionsJSON>>(
    "/auth/passkey/device_invite/begin",
    { invite_token: args.inviteToken },
    ANON,
  );

  const credential = await startRegistration({ optionsJSON: begin.options });

  return api.post<SessionResponse>("/auth/passkey/device_invite/finish", {
    credential,
    challenge_token: begin.challenge_token,
    nickname: args.nickname,
  }, ANON);
}


export async function fetchInvitePreview(code: string): Promise<InvitePreview> {
  const res = await fetch(`/api/v1/invites/${encodeURIComponent(code)}`);
  if (res.status === 404 || res.status === 410) return Promise.reject(new Error("Invite invalid or expired"));
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json() as Promise<InvitePreview>;
}

/** GET /setup: whether this instance needs its first account, and how
 *  people sign in — Fin's passkeys, fog alongside them, or fog alone. */
export function fetchSetupStatus(): Promise<SetupStatus> {
  return api.get<SetupStatus>("/setup");
}

/** Where "Sign in with fog" goes: the server starts the OpenID flow. */
export function fogSigninUrl(returnTo = "/"): string {
  return `/auth/oidc/start?return_to=${encodeURIComponent(returnTo)}`;
}
