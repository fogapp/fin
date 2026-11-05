import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, fireEvent, waitFor, within } from "@testing-library/react";

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

// The section hands files to the browser; the tests only care what it hands over.
vi.mock("@/lib/download", () => ({ downloadText: vi.fn(), downloadUrl: vi.fn() }));

import { api, clearToken } from "@/api/client";
import { downloadText, downloadUrl } from "@/lib/download";
import { renderApp } from "@/test/renderApp";

const apiMock = vi.mocked(api);

const me = (role: "admin" | "member") => ({
  user: { id: "u1", email: "owner@example.com", name: "Owner" },
  household: { id: "h1", name: "Home", role, workflow_log_level: "info", include_unvested_equity: false },
});

const MEMBERS = [
  { id: "m1", role: "admin", created_at: "2026-01-01T00:00:00Z", user: { id: "u1", email: "owner@example.com", name: "Owner" } },
  { id: "m2", role: "member", created_at: "2026-01-02T00:00:00Z", user: { id: "u2", email: "spouse@example.com", name: null } },
];

const COMPLETED = {
  id: "aaa111", status: "completed", progress: null, error: null,
  started_at: "2026-09-30T12:00:00Z", requested_by: "owner@example.com",
  bytes: 48_211_934, sha256: "9f2c11ab", created_at: "2026-09-30T12:00:05Z",
  expires_at: "2026-10-01T12:00:05Z", filename: "fin-20260930-120005.fogpack.tar",
};
const RUNNING = {
  id: "bbb222", status: "running", progress: "dumping database", error: null,
  started_at: "2026-09-30T13:00:00Z", requested_by: "owner@example.com",
  bytes: null, sha256: null, created_at: null, expires_at: null, filename: null,
};
const FAILED = { ...RUNNING, id: "ccc333", status: "failed", progress: null, error: "pg_dump exited 1: connection refused" };

const overview = (over: Record<string, unknown> = {}) => ({
  backups: [ COMPLETED ],
  address: { host: "fin.old.example", rp_id: "fin.old.example" },
  keys: [
    { name: "AR_ENCRYPTION_PRIMARY_KEY", fingerprint: "sha256:1e26c45bd594" },
    { name: "SECRET_KEY_BASE", fingerprint: "sha256:f5fb685346f7" },
  ],
  retention_hours: 24,
  last_restore: null,
  ...over,
});

function installGetStub(backups: unknown = overview(), role: "admin" | "member" = "admin") {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return me(role) as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/household_memberships") return MEMBERS as never;
    if (path === "/backups") {
      if (backups instanceof Error) throw backups;
      return backups as never;
    }
    return [] as never;
  });
}

const open = () => renderApp({ initialPath: "/settings#topic=backup", initialToken: "tok" });

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.delete.mockReset();
  vi.mocked(downloadText).mockReset();
  vi.mocked(downloadUrl).mockReset();
  vi.stubGlobal("fetch", vi.fn());
  apiMock.post.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);
  installGetStub();
});

describe("Settings → Backup: backups", () => {
  it("lists a finished backup with its size and who made it", async () => {
    open();

    expect(await screen.findByText("fin-20260930-120005.fogpack.tar")).toBeInTheDocument();
    expect(screen.getByText(/46 MB · owner@example\.com/)).toBeInTheDocument();
    expect(screen.getByText(/stays on the server for 24 hours/)).toBeInTheDocument();
  });

  it("shows the producer's progress and won't start a second backup while one runs", async () => {
    installGetStub(overview({ backups: [ RUNNING, COMPLETED ] }));
    open();

    expect(await screen.findByText("dumping database")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Creating backup/ })).toBeDisabled();
  });

  it("shows why a backup failed, with nothing to download", async () => {
    installGetStub(overview({ backups: [ FAILED ] }));
    open();

    expect(await screen.findByText("pg_dump exited 1: connection refused")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Download$/ })).not.toBeInTheDocument();
  });

  it("starts a backup via POST /backups", async () => {
    installGetStub(overview({ backups: [] }));
    open();

    expect(await screen.findByText("No backups yet.")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Create backup" }));

    await waitFor(() => expect(apiMock.post).toHaveBeenCalledWith("/backups"));
  });

  it("downloads through a ticketed URL rather than pulling the file into the page", async () => {
    apiMock.post.mockResolvedValueOnce({ url: "/api/v1/backups/aaa111/artifact?ticket=t1", expires_at: "2026-09-30T12:10:00Z" } as never);
    open();

    fireEvent.click(await screen.findByRole("button", { name: /Download$/ }));

    await waitFor(() => expect(apiMock.post).toHaveBeenCalledWith("/backups/aaa111/download"));
    await waitFor(() => expect(downloadUrl).toHaveBeenCalledWith("/api/v1/backups/aaa111/artifact?ticket=t1"));
  });

  it("deletes a backup behind a confirm", async () => {
    open();

    fireEvent.click(await screen.findByRole("button", { name: "Delete backup" }));
    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Delete" }));

    await waitFor(() => expect(apiMock.delete).toHaveBeenCalledWith("/backups/aaa111"));
  });
});

describe("Settings → Backup: instance keys", () => {
  const REVEALED = { keys: [
    { name: "AR_ENCRYPTION_PRIMARY_KEY", value: "primary-value", fingerprint: "sha256:1e26c45bd594" },
    { name: "SECRET_KEY_BASE", value: "skb-value", fingerprint: "sha256:f5fb685346f7" },
  ] };

  it("names the keys but fetches no values until asked", async () => {
    open();

    expect(await screen.findByText("AR_ENCRYPTION_PRIMARY_KEY")).toBeInTheDocument();
    expect(screen.getByText("SECRET_KEY_BASE")).toBeInTheDocument();
    expect(apiMock.post).not.toHaveBeenCalled();
  });

  it("does nothing when the reveal is cancelled", async () => {
    open();

    fireEvent.click(await screen.findByRole("button", { name: "Reveal keys" }));
    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument());
    expect(apiMock.post).not.toHaveBeenCalled();
  });

  it("reveals the values after a confirm, offers them as an .env, and hides them again", async () => {
    apiMock.post.mockResolvedValueOnce(REVEALED as never);
    open();

    fireEvent.click(await screen.findByRole("button", { name: "Reveal keys" }));
    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Reveal" }));

    expect(await screen.findByText("primary-value")).toBeInTheDocument();
    expect(apiMock.post).toHaveBeenCalledWith("/backups/keys");

    fireEvent.click(screen.getByRole("button", { name: /Download as \.env/ }));
    const [ filename, contents ] = vi.mocked(downloadText).mock.calls[0];
    expect(filename).toBe("fin-keys-fin.old.example.env");
    expect(contents).toContain("AR_ENCRYPTION_PRIMARY_KEY=primary-value\nSECRET_KEY_BASE=skb-value\n");

    fireEvent.click(screen.getByRole("button", { name: "Hide keys" }));
    expect(screen.queryByText("primary-value")).not.toBeInTheDocument();
  });

  it("says so when the instance runs without keys", async () => {
    installGetStub(overview({ keys: [] }));
    open();

    expect(await screen.findByText(/no keys set in its environment/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Reveal keys" })).not.toBeInTheDocument();
  });
});

describe("Settings → Backup: moving to a new address", () => {
  it("names the address passkeys are bound to and waits for a new one", async () => {
    open();

    expect(await screen.findByText("fin.old.example")).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: "Create link for spouse@example.com" })).toBeDisabled();
  });

  it("creates a sign-in link for a member at the new address", async () => {
    apiMock.post.mockResolvedValueOnce({
      token: "tok-1", expires_at: "2026-10-07T12:00:00Z", host: "fin.new.example",
      url: "https://fin.new.example/join-device?token=tok-1",
    } as never);
    open();

    fireEvent.change(await screen.findByLabelText("New address"), { target: { value: " fin.new.example " } });
    fireEvent.click(await screen.findByRole("button", { name: "Create link for spouse@example.com" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/device_invites", { address: "fin.new.example", user_id: "u2" });
    });
    expect(await screen.findByText("https://fin.new.example/join-device?token=tok-1")).toBeInTheDocument();
    expect(screen.getByText(/Works once, only at fin\.new\.example/)).toBeInTheDocument();
    // The owner's own row is still waiting for its link.
    expect(screen.getByRole("button", { name: "Create link for owner@example.com" })).toBeEnabled();
  });

  it("drops links made for an address that was then edited", async () => {
    apiMock.post.mockResolvedValueOnce({
      token: "tok-1", expires_at: "2026-10-07T12:00:00Z", host: "fin.new.example",
      url: "https://fin.new.example/join-device?token=tok-1",
    } as never);
    open();

    const input = await screen.findByLabelText("New address");
    fireEvent.change(input, { target: { value: "fin.new.example" } });
    fireEvent.click(await screen.findByRole("button", { name: "Create link for spouse@example.com" }));
    expect(await screen.findByText(/join-device\?token=tok-1/)).toBeInTheDocument();

    fireEvent.change(input, { target: { value: "fin.other.example" } });

    expect(screen.queryByText(/join-device\?token=tok-1/)).not.toBeInTheDocument();
  });

  it("shows the server's reason when the address is refused", async () => {
    apiMock.post.mockRejectedValueOnce(new Error("Enter the new address as a hostname or URL, e.g. fin.example.com"));
    open();

    fireEvent.change(await screen.findByLabelText("New address"), { target: { value: "not a host" } });
    fireEvent.click(await screen.findByRole("button", { name: "Create link for owner@example.com" }));

    expect(await screen.findByText(/Enter the new address as a hostname or URL/)).toBeInTheDocument();
  });
});

describe("Settings → Backup: access and history", () => {
  it("tells a non-admin member why there is nothing here, without asking the server", async () => {
    installGetStub(overview(), "member");
    open();

    expect(await screen.findByText("Only a household admin can create and download backups.")).toBeInTheDocument();
    expect(apiMock.get).not.toHaveBeenCalledWith("/backups");
  });

  it("passes on a refusal from the server", async () => {
    installGetStub(new Error("Only a household admin can manage backups."));
    open();

    expect(await screen.findByText("Only a household admin can manage backups.")).toBeInTheDocument();
  });

  it("notes a restore that moved the instance", async () => {
    installGetStub(overview({ last_restore: {
      restored_at: "2026-09-30T16:49:08Z", artifact_created_at: "2026-09-30T16:49:06Z",
      moved_from: "fin.older.example", moved_to: "fin.old.example",
    } }));
    open();

    expect(await screen.findByText("fin.older.example")).toBeInTheDocument();
    expect(screen.getByText(/This instance was restored on/)).toBeInTheDocument();
  });
});
