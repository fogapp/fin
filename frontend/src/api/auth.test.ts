import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Stub the WebAuthn browser library before importing the module under test.
vi.mock("@simplewebauthn/browser", () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

import { registerPasskey, loginWithPasskey, fetchInvitePreview } from "./auth";
import { startRegistration, startAuthentication } from "@simplewebauthn/browser";

const startRegMock = vi.mocked(startRegistration);
const startAuthMock = vi.mocked(startAuthentication);

describe("auth helpers", () => {
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    startRegMock.mockReset();
    startAuthMock.mockReset();
  });

  afterEach(() => vi.unstubAllGlobals());

  function jsonResponse(body: unknown, { status = 200 }: { status?: number } = {}) {
    return Promise.resolve({
      ok: status >= 200 && status < 300,
      status,
      json: () => Promise.resolve(body),
    } as Response);
  }

  describe("registerPasskey", () => {
    it("runs begin → WebAuthn → finish and returns the session response", async () => {
      const beginOptions = { challenge: "abc" };
      fetchMock
        .mockReturnValueOnce(jsonResponse({ options: beginOptions, challenge_token: "tok1" }))
        .mockReturnValueOnce(jsonResponse({
          token: "session-token",
          user: { id: "u1", email: "x@y.com", name: "X" },
          household: { id: "h1", name: "House", role: "admin" },
        }));
      startRegMock.mockResolvedValue({ id: "cred-id" } as never);

      const result = await registerPasskey({ email: "x@y.com", name: "X", inviteCode: "code1", nickname: "MacBook" });

      expect(fetchMock).toHaveBeenNthCalledWith(
        1,
        "/api/v1/auth/passkey/register/begin",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ email: "x@y.com", name: "X", invite_code: "code1" }),
        }),
      );
      expect(startRegMock).toHaveBeenCalledWith({ optionsJSON: beginOptions });
      expect(fetchMock).toHaveBeenNthCalledWith(
        2,
        "/api/v1/auth/passkey/register/finish",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({
            credential: { id: "cred-id" },
            challenge_token: "tok1",
            nickname: "MacBook",
          }),
        }),
      );
      expect(result.token).toBe("session-token");
      expect(result.household.id).toBe("h1");
    });

    it("propagates the error message from a failed begin call", async () => {
      fetchMock.mockReturnValueOnce(jsonResponse({ error: "Email already used" }, { status: 422 }));
      await expect(registerPasskey({ email: "dup@x.com" })).rejects.toThrow("Email already used");
      expect(startRegMock).not.toHaveBeenCalled();
    });

    it("propagates WebAuthn errors without calling finish", async () => {
      fetchMock.mockReturnValueOnce(jsonResponse({ options: {}, challenge_token: "tok" }));
      startRegMock.mockRejectedValue(new Error("user canceled"));
      await expect(registerPasskey({ email: "x@y.com" })).rejects.toThrow("user canceled");
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });
  });

  describe("loginWithPasskey", () => {
    it("posts to login/begin and login/finish with the challenge_token", async () => {
      fetchMock
        .mockReturnValueOnce(jsonResponse({ options: { challenge: "L" }, challenge_token: "ltok" }))
        .mockReturnValueOnce(jsonResponse({
          token: "tok",
          user: { id: "u", email: "x", name: null },
          household: { id: "h", name: "H", role: null },
        }));
      startAuthMock.mockResolvedValue({ id: "assertion" } as never);

      const result = await loginWithPasskey({ email: "x@y.com" });

      expect(fetchMock.mock.calls[0][0]).toBe("/api/v1/auth/passkey/login/begin");
      expect(fetchMock.mock.calls[0][1].body).toBe(JSON.stringify({ email: "x@y.com" }));
      expect(startAuthMock).toHaveBeenCalledWith({ optionsJSON: { challenge: "L" } });
      expect(fetchMock.mock.calls[1][0]).toBe("/api/v1/auth/passkey/login/finish");
      expect(fetchMock.mock.calls[1][1].body).toBe(
        JSON.stringify({ credential: { id: "assertion" }, challenge_token: "ltok" }),
      );
      expect(result.token).toBe("tok");
    });

    it("passes an empty body when no email is provided (conditional-UI flow)", async () => {
      fetchMock
        .mockReturnValueOnce(jsonResponse({ options: {}, challenge_token: "t" }))
        .mockReturnValueOnce(jsonResponse({ token: "ok", user: { id: "u", email: "x", name: null }, household: { id: "h", name: "H", role: null } }));
      startAuthMock.mockResolvedValue({} as never);

      await loginWithPasskey();
      expect(fetchMock.mock.calls[0][1].body).toBe(JSON.stringify({ email: undefined }));
    });
  });

  describe("fetchInvitePreview", () => {
    it("URI-encodes the code and returns the invite payload", async () => {
      const payload = {
        code: "abc/xyz",
        role: "member",
        expires_at: "2026-12-31",
        household: { id: "h1", name: "Test" },
      };
      fetchMock.mockReturnValueOnce(jsonResponse(payload));

      const result = await fetchInvitePreview("abc/xyz");
      expect(fetchMock).toHaveBeenCalledWith("/api/v1/invites/abc%2Fxyz");
      expect(result).toEqual(payload);
    });

    it("rejects with a friendly message on 404", async () => {
      fetchMock.mockReturnValueOnce(jsonResponse({}, { status: 404 }));
      await expect(fetchInvitePreview("missing")).rejects.toThrow("Invite invalid or expired");
    });

    it("rejects with a friendly message on 410 Gone", async () => {
      fetchMock.mockReturnValueOnce(jsonResponse({}, { status: 410 }));
      await expect(fetchInvitePreview("expired")).rejects.toThrow("Invite invalid or expired");
    });

    it("throws a generic HTTP error on other failures", async () => {
      fetchMock.mockReturnValueOnce(jsonResponse({}, { status: 500 }));
      await expect(fetchInvitePreview("x")).rejects.toThrow("HTTP 500");
    });
  });
});
