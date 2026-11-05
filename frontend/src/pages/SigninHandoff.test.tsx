import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

vi.mock("@simplewebauthn/browser", () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return { ...actual, api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() } };
});

import { api, getToken } from "@/api/client";
import { startAuthentication } from "@simplewebauthn/browser";
import { renderApp } from "@/test/renderApp";

const apiMock = vi.mocked(api);
const startAuthMock = vi.mocked(startAuthentication);

const SESSION = {
  token: "session-token",
  user: { id: "u1", email: "kim@example.com", name: "Kim" },
  household: { id: "h1", name: "Home", role: "member" },
};

// jsdom's window.location.assign isn't configurable for spyOn, so swap the
// whole location object for each test.
const originalLocation = window.location;
let assignMock: ReturnType<typeof vi.fn>;
let fetchMock: ReturnType<typeof vi.fn>;

function jsonResponse(body: unknown, status = 200) {
  return Promise.resolve({ ok: status >= 200 && status < 300, status, json: () => Promise.resolve(body) } as Response);
}

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.get.mockResolvedValue({ setup_required: false, signin: { enabled: true, fog_only: false } } as never);
  startAuthMock.mockReset();
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  assignMock = vi.fn();
  Object.defineProperty(window, "location", {
    configurable: true,
    value: { ...originalLocation, pathname: "/", hash: "", search: "", assign: assignMock },
  });
});

afterEach(() => {
  Object.defineProperty(window, "location", { configurable: true, value: originalLocation });
  vi.unstubAllGlobals();
});

describe("/auth/complete", () => {
  it("trades the one-time code for a session and goes where the person was headed", async () => {
    apiMock.post.mockResolvedValue(SESSION as never);
    renderApp({ initialPath: "/auth/complete#handoff=abc&return_to=%2Fcashflow" });

    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/cashflow"));
    expect(apiMock.post).toHaveBeenCalledWith("/handoff", { handoff: "abc" }, { anonymous: true });
    expect(getToken()).toBe("session-token");
  });

  it("never follows a return path off this host", async () => {
    apiMock.post.mockResolvedValue(SESSION as never);
    renderApp({ initialPath: "/auth/complete#handoff=abc&return_to=%2F%2Fevil.example%2F" });

    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/"));
  });

  it("takes a recovery link even with an old session in this browser", async () => {
    apiMock.post.mockResolvedValue(SESSION as never);
    renderApp({ initialPath: "/auth/complete#handoff=abc&return_to=%2F", initialToken: "stale" });

    await waitFor(() => expect(getToken()).toBe("session-token"));
    expect(assignMock).toHaveBeenCalledWith("/");
  });

  it("says so when the code has expired", async () => {
    apiMock.post.mockRejectedValue(new Error("This sign-in link has expired; sign in again."));
    renderApp({ initialPath: "/auth/complete#handoff=old" });

    expect(await screen.findByText(/has expired/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Back to sign-in" })).toBeInTheDocument();
    expect(getToken()).toBeNull();
  });
});

describe("/auth/link", () => {
  const LINK = "/auth/link#pending=sealed";

  it("connects an existing account once its owner signs in with their Fin passkey", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/link/begin") return { options: { challenge: "c" }, challenge_token: "ct" } as never;
      if (path === "/auth/passkey/link/finish") return { link_token: "proof" } as never;
      if (path === "/handoff") return SESSION as never;
      throw new Error(`unexpected ${path}`);
    });
    startAuthMock.mockResolvedValue({ id: "assertion" } as never);
    fetchMock.mockReturnValue(jsonResponse({ handoff: "h1", return_to: "/cashflow" }));

    renderApp({ initialPath: LINK });
    await userEvent.setup().click(
      await screen.findByRole("button", { name: "Sign in with your Fin passkey to connect it" }),
    );

    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/cashflow"));
    expect(apiMock.post).toHaveBeenCalledWith("/auth/passkey/link/begin", { pending: "sealed", email: undefined }, { anonymous: true });
    const [ url, init ] = fetchMock.mock.calls[0];
    expect(url).toBe("/auth/oidc/link");
    expect(init.headers.Authorization).toBe("Bearer proof");
    expect(JSON.parse(init.body)).toEqual({ pending: "sealed" });
    expect(apiMock.post).toHaveBeenCalledWith("/handoff", { handoff: "h1" }, { anonymous: true });
    expect(getToken()).toBe("session-token");
  });

  it("starts fresh without a passkey", async () => {
    apiMock.post.mockResolvedValue(SESSION as never);
    fetchMock.mockReturnValue(jsonResponse({ handoff: "h1", return_to: "/" }));

    renderApp({ initialPath: LINK });
    await userEvent.setup().click(await screen.findByRole("button", { name: /start fresh/ }));

    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/"));
    const [ , init ] = fetchMock.mock.calls[0];
    expect(init.headers.Authorization).toBeUndefined();
    expect(JSON.parse(init.body)).toEqual({ pending: "sealed", fresh: "true" });
    expect(startAuthMock).not.toHaveBeenCalled();
  });

  it("says so when the account can't be connected", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/link/begin") return { options: { challenge: "c" }, challenge_token: "ct" } as never;
      if (path === "/auth/passkey/link/finish") return { link_token: "proof" } as never;
      throw new Error(`unexpected ${path}`);
    });
    startAuthMock.mockResolvedValue({ id: "assertion" } as never);
    fetchMock.mockReturnValue(jsonResponse({}, 400));

    renderApp({ initialPath: LINK });
    await userEvent.setup().click(
      await screen.findByRole("button", { name: "Sign in with your Fin passkey to connect it" }),
    );

    expect(await screen.findByText(/can't be connected/)).toBeInTheDocument();
    expect(assignMock).not.toHaveBeenCalled();
    expect(getToken()).toBeNull();
  });

  it("offers to sign in again when there is nothing to connect", async () => {
    renderApp({ initialPath: "/auth/link" });
    expect(await screen.findByText(/nothing to connect/)).toBeInTheDocument();
  });
});

describe("/login with fog", () => {
  it("offers fog beside the passkey", async () => {
    renderApp({ initialPath: "/login" });
    expect(await screen.findByRole("button", { name: "Sign in with fog" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Sign in with passkey/ })).toBeInTheDocument();

    await userEvent.setup().click(screen.getByRole("button", { name: "Sign in with fog" }));
    expect(assignMock).toHaveBeenCalledWith("/auth/oidc/start?return_to=%2F");
  });

  it("offers only fog once Fin signs everyone in with fog", async () => {
    apiMock.get.mockResolvedValue({ setup_required: false, signin: { enabled: true, fog_only: true } } as never);
    renderApp({ initialPath: "/login" });

    expect(await screen.findByRole("button", { name: "Sign in with fog" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Sign in with passkey/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/Create an account/)).not.toBeInTheDocument();
  });

  it("says why a fog sign-in did not finish", async () => {
    renderApp({ initialPath: "/login#signin_error=passkey_required" });
    expect(await screen.findByText(/sign in to fog with a passkey/)).toBeInTheDocument();
  });

  it("closes registration once Fin signs everyone in with fog", async () => {
    apiMock.get.mockResolvedValue({ setup_required: false, signin: { enabled: true, fog_only: true } } as never);
    renderApp({ initialPath: "/register" });

    expect(await screen.findByText("Fin signs everyone in with fog")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Create passkey/ })).not.toBeInTheDocument();
  });
});
