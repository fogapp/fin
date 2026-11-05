import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

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

import { api, clearToken } from "@/api/client";
import { renderApp } from "@/test/renderApp";

const apiMock = vi.mocked(api);

const NOTIFICATIONS = {
  notifications: [
    { id: "n1", title: "Low balance", body: "Checking fell below $500", severity: "critical",
      subject_type: "Account", subject_id: "a1", read_at: null, created_at: "2026-07-02T10:00:00Z" },
    { id: "n2", title: "Sync finished", body: null, severity: "info",
      subject_type: "PlaidItem", subject_id: "p1", read_at: null, created_at: "2026-07-02T09:00:00Z" },
    { id: "n3", title: "Old news", body: "Already seen", severity: "warning",
      subject_type: null, subject_id: null, read_at: "2026-07-01T00:00:00Z", created_at: "2026-07-01T00:00:00Z" },
  ],
  unread_count: 2,
};

beforeEach(() => {
  clearToken();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  apiMock.post.mockResolvedValue({} as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                 household: { id: "h1", name: "H", role: "admin" } } as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/notifications") return NOTIFICATIONS as never;
    if (path === "/tags") return [] as never;
    return [] as never;
  });
});

describe("Notification bell", () => {
  it("shows the unread count badge", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    expect(await screen.findByRole("button", { name: "Notifications (2 unread)" })).toBeInTheDocument();
    expect(screen.getByText("2")).toBeInTheDocument();
  });

  it("opens a panel listing notifications and marks one read on click", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: "Notifications (2 unread)" }));

    expect(await screen.findByText("Low balance")).toBeInTheDocument();
    expect(screen.getByText("Checking fell below $500")).toBeInTheDocument();
    expect(screen.getByText("Sync finished")).toBeInTheDocument();
    expect(screen.getByText("Old news")).toBeInTheDocument();

    await userEvent.click(screen.getByText("Low balance"));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/notifications/n1/read", {});
    });
  });

  it("does not POST when clicking an already-read notification", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: "Notifications (2 unread)" }));
    await userEvent.click(await screen.findByText("Old news"));

    expect(apiMock.post).not.toHaveBeenCalled();
  });

  it("'Mark all read' POSTs /notifications/read_all", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: "Notifications (2 unread)" }));
    await userEvent.click(screen.getByRole("button", { name: "Mark all read" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/notifications/read_all", {});
    });
  });

  it("a notification with a destination navigates there and closes the panel", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return {
        notifications: [
          { id: "n9", title: "Your July 2026 review is ready", body: null, severity: "info",
            href: "/review?month=2026-07", subject_type: "Household", subject_id: "h1",
            read_at: null, created_at: "2026-08-01T08:00:00Z" },
        ],
        unread_count: 1,
      } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: "Notifications (1 unread)" }));
    await userEvent.click(await screen.findByText("Your July 2026 review is ready"));

    expect(await screen.findByRole("heading", { name: "Review · July 2026" })).toBeInTheDocument();
    expect(apiMock.post).toHaveBeenCalledWith("/notifications/n9/read", {});
  });

  it("marks error- and critical-severity notifications with the negative dot", async () => {
    // The backend's Severity is info|warning|error|critical; "error" used to
    // fall through to the neutral info dot.
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return {
        notifications: [
          { id: "e1", title: "Sync failed", body: null, severity: "error", href: null,
            subject_type: null, subject_id: null, read_at: null, created_at: "2026-07-02T10:00:00Z" },
          { id: "c1", title: "Balance critical", body: null, severity: "critical", href: null,
            subject_type: null, subject_id: null, read_at: null, created_at: "2026-07-02T09:00:00Z" },
          { id: "i1", title: "All good", body: null, severity: "info", href: null,
            subject_type: null, subject_id: null, read_at: null, created_at: "2026-07-02T08:00:00Z" },
        ],
        unread_count: 3,
      } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows", initialToken: "tok" });
    await userEvent.click(await screen.findByRole("button", { name: "Notifications (3 unread)" }));

    const dotFor = async (title: string) =>
      (await screen.findByText(title)).closest("button")!.querySelector("span.rounded-full")!;

    expect((await dotFor("Sync failed")).className).toContain("bg-negative");
    expect((await dotFor("Balance critical")).className).toContain("bg-negative");
    expect((await dotFor("All good")).className).not.toContain("bg-negative");
  });

  it("hides the badge when everything is read", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    expect(await screen.findByRole("button", { name: "Notifications" })).toBeInTheDocument();
  });
});
