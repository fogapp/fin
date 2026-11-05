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

import { api } from "@/api/client";
import { renderApp } from "@/test/renderApp";

const apiMock = vi.mocked(api);

const ASKED = {
  consumer: "newtab",
  offer: { id: "finance", title: "Finances", blurb: "This app can read the household's accounts and change nothing." },
  state: "pending",
  expires_at: "2026-10-14T12:30:00Z",
};

const originalLocation = window.location;
let assignMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  assignMock = vi.fn();
  Object.defineProperty(window, "location", {
    configurable: true,
    value: { ...originalLocation, pathname: "/", hash: "", search: "", assign: assignMock },
  });
});

afterEach(() => {
  Object.defineProperty(window, "location", { configurable: true, value: originalLocation });
});

describe("/connect/<ticket>", () => {
  it("shows who is asking and what it grants, and approval goes back to fog", async () => {
    apiMock.get.mockResolvedValue(ASKED as never);
    apiMock.post.mockResolvedValue({
      state: "approved",
      return_to: "https://fog.example/api/integrations/return?state=abc&result=approved",
    } as never);
    renderApp({ initialPath: "/connect/t1", initialToken: "session" });

    expect(await screen.findByRole("heading", { name: "Let newtab read Fin?" })).toBeInTheDocument();
    expect(screen.getByText(/change nothing/)).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/fog_connections/t1");

    await userEvent.setup().click(screen.getByRole("button", { name: "Approve" }));

    expect(apiMock.post).toHaveBeenCalledWith("/fog_connections/t1/approve");
    await waitFor(() =>
      expect(assignMock).toHaveBeenCalledWith("https://fog.example/api/integrations/return?state=abc&result=approved"),
    );
  });

  it("declining goes back to fog with the answer", async () => {
    apiMock.get.mockResolvedValue(ASKED as never);
    apiMock.post.mockResolvedValue({
      state: "declined",
      return_to: "https://fog.example/api/integrations/return?state=abc&result=declined",
    } as never);
    renderApp({ initialPath: "/connect/t1", initialToken: "session" });

    await userEvent.setup().click(await screen.findByRole("button", { name: "Decline" }));

    expect(apiMock.post).toHaveBeenCalledWith("/fog_connections/t1/decline");
    await waitFor(() =>
      expect(assignMock).toHaveBeenCalledWith("https://fog.example/api/integrations/return?state=abc&result=declined"),
    );
  });

  it("offers no buttons once the request has expired", async () => {
    apiMock.get.mockResolvedValue({ ...ASKED, state: "expired" } as never);
    renderApp({ initialPath: "/connect/t1", initialToken: "session" });

    expect(await screen.findByText(/expired before anyone answered/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Approve" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Decline" })).not.toBeInTheDocument();
  });

  it("says why when the request can't be shown", async () => {
    apiMock.get.mockRejectedValue(new Error("Only a household admin can let an app read Fin."));
    renderApp({ initialPath: "/connect/t1", initialToken: "session" });

    expect(await screen.findByRole("alert")).toHaveTextContent("Only a household admin");
    expect(screen.queryByRole("button", { name: "Approve" })).not.toBeInTheDocument();
  });

  it("asks for a sign-in first, and comes back here after it", async () => {
    apiMock.get.mockResolvedValue({ setup_required: false, signin: { enabled: true, fog_only: false } } as never);
    renderApp({ initialPath: "/connect/t1" });

    expect(await screen.findByRole("button", { name: "Sign in with fog" })).toBeInTheDocument();
    await userEvent.setup().click(screen.getByRole("button", { name: "Sign in with fog" }));
    expect(assignMock).toHaveBeenCalledWith("/auth/oidc/start?return_to=%2Fconnect%2Ft1");
  });
});
