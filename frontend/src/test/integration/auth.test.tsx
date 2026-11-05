import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// Mock WebAuthn before importing anything that pulls it in.
vi.mock("@simplewebauthn/browser", () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

// Mock the api module wholesale. Every endpoint defaults to {} so pages
// load without hanging; individual tests override the calls they care about.
vi.mock("@/api/client", async () => {
  // Use the real getToken/setToken/clearToken (localStorage-backed) so the
  // AuthProvider sees the same token store the helper writes to.
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: {
      get: vi.fn(),
      post: vi.fn(),
      patch: vi.fn(),
      delete: vi.fn(),
    },
  };
});

import { api, clearToken, getToken } from "@/api/client";
import { startAuthentication, startRegistration } from "@simplewebauthn/browser";
import { renderApp } from "@/test/renderApp";

const apiMock = vi.mocked(api);
const startAuthMock = vi.mocked(startAuthentication);
const startRegMock = vi.mocked(startRegistration);

// Default GET handlers so pages render. Routes hit a lot of endpoints —
// we return enough shape for them not to crash.
function installDefaultApiStubs() {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") {
      return { user: { id: "u1", email: "x@y.com", name: "X" },
               household: { id: "h1", name: "Test Household", role: "admin" } } as never;
    }
    if (path === "/preferences") return { data: {} } as never;
    if (path.startsWith("/dashboard")) {
      return {
        stats: { transactions: 0, portfolio_value: 0,
                 unrealized: 0, cost_basis: 0, income_ytd: 0 },
        compact_stats: { spend: 0, income: 0, cc_count: 0, cc_avg: 0,
                         spend_change: 0, income_change: 0,
                         cc_count_change: 0, cc_avg_change: 0 },
        portfolio_chart: {}, allocation: {}, monthly_spend: {}, income_series: {},
      } as never;
    }
    if (path.startsWith("/cash_transactions")) return [] as never;
    return [] as never;
  });
}

beforeEach(() => {
  clearToken();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  startAuthMock.mockReset();
  startRegMock.mockReset();

  // Stub the global fetch still used directly by fetchInvitePreview.
  vi.stubGlobal("fetch", vi.fn());

  // Default resolutions so background fetches (usePreferences etc.) don't
  // explode with `undefined.catch()`.
  apiMock.post.mockResolvedValue(undefined as never);
  apiMock.patch.mockResolvedValue(undefined as never);
  apiMock.delete.mockResolvedValue(undefined as never);

  installDefaultApiStubs();
});

function jsonResponse(body: unknown, { status = 200 }: { status?: number } = {}) {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(body),
  } as Response);
}

// ── 1. Landing → Login → Dashboard ────────────────────────────────────────────

describe("auth flow: Landing → Login → Dashboard", () => {
  it("clicking 'I have an account' on Landing triggers passkey login + lands on Dashboard", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/login/begin") {
        return { options: { challenge: "c" }, challenge_token: "tok" } as never;
      }
      if (path === "/auth/passkey/login/finish") {
        return {
          token: "session-token",
          user: { id: "u1", email: "x@y.com", name: "X" },
          household: { id: "h1", name: "Test", role: "admin" },
        } as never;
      }
      return undefined as never;
    });
    startAuthMock.mockResolvedValue({ id: "assertion" } as never);

    renderApp({ initialPath: "/" });

    expect(screen.getByText(/A quiet place for your money/)).toBeInTheDocument();
    await userEvent.setup().click(screen.getByRole("button", { name: /I have an account/i }));

    await waitFor(() => expect(screen.getByRole("link", { name: /Investments/i })).toBeInTheDocument());
    expect(getToken()).toBe("session-token");
  });

  it("/login submits passkey login and routes to Dashboard on success", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/login/begin") {
        return { options: { challenge: "c" }, challenge_token: "tok" } as never;
      }
      if (path === "/auth/passkey/login/finish") {
        return {
          token: "abc", user: { id: "u1", email: "x", name: null },
          household: { id: "h1", name: "X", role: null },
        } as never;
      }
      return undefined as never;
    });
    startAuthMock.mockResolvedValue({ id: "a" } as never);

    renderApp({ initialPath: "/login" });

    expect(screen.getByText("Welcome back")).toBeInTheDocument();
    await userEvent.setup().click(screen.getByRole("button", { name: /Sign in with passkey/i }));

    await waitFor(() => expect(screen.getByRole("link", { name: /Investments/i })).toBeInTheDocument());
    expect(getToken()).toBe("abc");
  });

  it("/login shows the API error message when register/begin fails", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/login/begin") throw new Error("Unknown user");
      return undefined as never;
    });

    renderApp({ initialPath: "/login" });
    await userEvent.setup().click(screen.getByRole("button", { name: /Sign in with passkey/i }));

    expect(await screen.findByText("Unknown user")).toBeInTheDocument();
    expect(getToken()).toBeNull();
  });

  it("/login maps WebAuthn NotAllowedError (no-credential) to the friendly hint (F2)", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/login/begin") {
        return { options: {}, challenge_token: "t" } as never;
      }
      return undefined as never;
    });
    const notAllowed = Object.assign(new Error("The operation either timed out or was not allowed."),
                                     { name: "NotAllowedError" });
    startAuthMock.mockRejectedValue(notAllowed);

    renderApp({ initialPath: "/login" });
    await userEvent.setup().click(screen.getByRole("button", { name: /Sign in with passkey/i }));

    expect(await screen.findByText(/No passkey for this device/i)).toBeInTheDocument();
  });

  it("Landing maps WebAuthn NotAllowedError to a /login redirect (F2)", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/login/begin") {
        return { options: {}, challenge_token: "t" } as never;
      }
      return undefined as never;
    });
    const notAllowed = Object.assign(new Error("The operation either timed out or was not allowed."),
                                     { name: "NotAllowedError" });
    startAuthMock.mockRejectedValue(notAllowed);

    renderApp({ initialPath: "/" });
    await userEvent.setup().click(screen.getByRole("button", { name: /I have an account/i }));

    // Landing redirected to /login → the /login page header shows "Welcome back"
    expect(await screen.findByText("Welcome back")).toBeInTheDocument();
  });
});

// ── 2. Landing → Register → Dashboard ─────────────────────────────────────────

describe("auth flow: Register → Dashboard", () => {
  it("/register submits passkey registration and routes to Dashboard on success", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/register/begin") {
        return { options: { challenge: "c" }, challenge_token: "tok" } as never;
      }
      if (path === "/auth/passkey/register/finish") {
        return {
          token: "reg-token", user: { id: "u2", email: "new@x.com", name: "New" },
          household: { id: "h1", name: "H", role: "admin" },
        } as never;
      }
      return undefined as never;
    });
    startRegMock.mockResolvedValue({ id: "cred" } as never);

    renderApp({ initialPath: "/register" });

    const user = userEvent.setup();
    await user.type(screen.getByLabelText(/Email/i), "new@x.com");
    await user.click(screen.getByRole("button", { name: /Create passkey/i }));

    await waitFor(() => expect(screen.getByRole("link", { name: /Investments/i })).toBeInTheDocument());
    expect(getToken()).toBe("reg-token");
  });

  it("/register?invite=ABC shows the household name in the preview", async () => {
    const fetchMock = vi.mocked(fetch as unknown as ReturnType<typeof vi.fn>);
    fetchMock.mockReturnValueOnce(jsonResponse({
      code: "ABC", role: "member", expires_at: null,
      household: { id: "h-other", name: "Other House" },
    }));

    renderApp({ initialPath: "/register?invite=ABC" });

    expect(await screen.findByText(/Other House/)).toBeInTheDocument();
    // Role chip says "member"
    expect(screen.getByText(/member/)).toBeInTheDocument();
  });

  it("/register?invite=BAD shows a friendly error for a missing/expired invite", async () => {
    const fetchMock = vi.mocked(fetch as unknown as ReturnType<typeof vi.fn>);
    fetchMock.mockReturnValueOnce(jsonResponse({}, { status: 404 }));

    renderApp({ initialPath: "/register?invite=BAD" });
    expect(await screen.findByText(/Invite invalid or expired/)).toBeInTheDocument();
  });

  it("clears the invite preview when the user navigates to /register without an invite (F4)", async () => {
    const fetchMock = vi.mocked(fetch as unknown as ReturnType<typeof vi.fn>);
    fetchMock.mockReturnValue(jsonResponse({
      code: "ABC", role: "member", expires_at: null,
      household: { id: "h-other", name: "Other House" },
    }));

    // Start on the invited URL — preview appears.
    const { unmount } = renderApp({ initialPath: "/register?invite=ABC" });
    expect(await screen.findByText(/Other House/)).toBeInTheDocument();
    unmount();

    // Mount a fresh tree at /register with no invite param.
    renderApp({ initialPath: "/register" });

    await waitFor(() => {
      expect(screen.queryByText(/Joining/)).toBeNull();
      expect(screen.getByText(/Pick an email/)).toBeInTheDocument();
    });
  });
});

// ── 3. Already-signed-in initial load ─────────────────────────────────────────

describe("auth flow: token persistence", () => {
  it("with a token in localStorage, the initial render lands on Dashboard", async () => {
    renderApp({ initialPath: "/", initialToken: "preloaded-token" });

    await waitFor(() => expect(screen.getByRole("link", { name: /Investments/i })).toBeInTheDocument());
    // No auth API calls happen — we never hit /auth/passkey/login/* on render.
    expect(getToken()).toBe("preloaded-token");
  });

  it("an unauthenticated user hitting a protected URL is bounced to Landing", () => {
    renderApp({ initialPath: "/transactions" });
    // Routes table maps "*" → "/" when isAuthenticated is false.
    expect(screen.getByText(/A quiet place for your money/)).toBeInTheDocument();
  });
});

// ── 4. Expired token → 401 → global handler clears token + routes to login ───

describe("auth flow: global 401 handler (F1 regression)", () => {
  it("clears the token and redirects to /login when any query returns 401", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path.startsWith("/dashboard")) throw new Error("unauthorized");
      return [] as never;
    });

    // jsdom's window.location.assign isn't configurable for spyOn, so swap
    // the whole location object for the duration of the test.
    const originalLocation = window.location;
    const assignMock = vi.fn();
    Object.defineProperty(window, "location", {
      configurable: true,
      value: { ...originalLocation, pathname: "/", assign: assignMock },
    });

    try {
      renderApp({ initialPath: "/", initialToken: "expired-token", useAppClient: true });

      await waitFor(() => {
        expect(getToken()).toBeNull();
        expect(assignMock).toHaveBeenCalledWith("/login");
      });
    } finally {
      Object.defineProperty(window, "location", {
        configurable: true,
        value: originalLocation,
      });
    }
  });
});

// ── 5. Logout ─────────────────────────────────────────────────────────────────

describe("auth flow: logout", () => {
  it("logout clears the token and routes back to Landing", async () => {
    renderApp({ initialPath: "/settings", initialToken: "preloaded-token" });

    // Wait for the Settings page to be authenticated-mounted
    await waitFor(() => expect(getToken()).toBe("preloaded-token"));

    // Sign out lives in the avatar dropdown in the page header
    await userEvent.setup().click(await screen.findByRole("button", { name: /Account menu/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /Sign out/i }));

    await waitFor(() => expect(getToken()).toBeNull());
    await waitFor(() => expect(screen.getByText(/A quiet place for your money/)).toBeInTheDocument());
  });
});
