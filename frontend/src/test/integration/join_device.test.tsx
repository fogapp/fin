import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, fireEvent, waitFor } from "@testing-library/react";

vi.mock("@simplewebauthn/browser", () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api, clearToken, getToken } from "@/api/client";
import { startRegistration } from "@simplewebauthn/browser";
import { renderApp } from "@/test/renderApp";

const apiMock = vi.mocked(api);
const startRegMock = vi.mocked(startRegistration);

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  startRegMock.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  apiMock.post.mockResolvedValue({} as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  // Post-login the app tree renders; keep authenticated pages from hanging.
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") {
      return { user: { id: "u1", email: "x@y.com", name: "X" },
               household: { id: "h1", name: "Home", role: "admin" } } as never;
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
    return [] as never;
  });
});

describe("JoinDevice page", () => {
  it("shows an invalid-link message when the token param is missing", () => {
    renderApp({ initialPath: "/join-device" });

    expect(screen.getByText("Invalid link")).toBeInTheDocument();
    expect(screen.getByText(/missing or malformed/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Register passkey/i })).toBeNull();
  });

  it("renders the registration form when a token is present", () => {
    renderApp({ initialPath: "/join-device?token=inv-tok" });

    expect(screen.getByText("Register this device")).toBeInTheDocument();
    expect(screen.getByPlaceholderText(/MacBook Pro, iPhone 15/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Register passkey/i })).toBeInTheDocument();
  });

  it("registers the device: begin → WebAuthn ceremony → finish, then signs in", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/device_invite/begin") {
        return { options: { challenge: "c" }, challenge_token: "ch-tok" } as never;
      }
      if (path === "/auth/passkey/device_invite/finish") {
        return {
          token: "session-token",
          user: { id: "u1", email: "x@y.com", name: "X" },
          household: { id: "h1", name: "Home", role: "admin" },
        } as never;
      }
      return {} as never;
    });
    startRegMock.mockResolvedValue({ id: "new-credential" } as never);

    renderApp({ initialPath: "/join-device?token=inv-tok" });

    fireEvent.change(screen.getByPlaceholderText(/MacBook Pro, iPhone 15/), {
      target: { value: "Work laptop" },
    });
    fireEvent.click(screen.getByRole("button", { name: /Register passkey/i }));

    await waitFor(() => expect(getToken()).toBe("session-token"));

    // begin was called with the invite token from the URL, anonymously
    expect(apiMock.post).toHaveBeenCalledWith(
      "/auth/passkey/device_invite/begin",
      { invite_token: "inv-tok" },
      { anonymous: true },
    );

    // the WebAuthn ceremony ran with the server's options
    expect(startRegMock).toHaveBeenCalledWith({ optionsJSON: { challenge: "c" } });

    // finish was called with the credential, challenge token, and nickname
    expect(apiMock.post).toHaveBeenCalledWith(
      "/auth/passkey/device_invite/finish",
      {
        credential: { id: "new-credential" },
        challenge_token: "ch-tok",
        nickname: "Work laptop",
      },
      { anonymous: true },
    );
  });

  it("shows the API error message when the invite is invalid or expired", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/auth/passkey/device_invite/begin") throw new Error("Invite expired");
      return {} as never;
    });

    renderApp({ initialPath: "/join-device?token=stale-tok" });

    fireEvent.click(screen.getByRole("button", { name: /Register passkey/i }));

    expect(await screen.findByText("Invite expired")).toBeInTheDocument();
    expect(getToken()).toBeNull();
    // The form is still available for another attempt.
    expect(screen.getByRole("button", { name: /Register passkey/i })).toBeEnabled();
  });
});
