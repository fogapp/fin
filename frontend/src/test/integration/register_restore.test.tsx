import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, fireEvent, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

vi.mock("@simplewebauthn/browser", () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn(), upload: vi.fn() },
  };
});

import { api, clearToken } from "@/api/client";
import { renderApp } from "@/test/renderApp";

const apiMock = vi.mocked(api);

const artifact = () => new File([ "tar bytes" ], "fin-20260930-120005.fogpack.tar", { type: "application/x-tar" });

function freshInstance(fresh: boolean) {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/setup") return { setup_required: fresh } as never;
    return {} as never;
  });
}

async function openRestore() {
  renderApp({ initialPath: "/register" });
  fireEvent.click(await screen.findByRole("button", { name: /Restore from a backup instead/ }));
  const input = document.querySelector('input[type="file"]') as HTMLInputElement;
  await userEvent.upload(input, artifact());
}

beforeEach(() => {
  clearToken();
  apiMock.get.mockReset();
  apiMock.upload.mockReset();
  vi.stubGlobal("fetch", vi.fn());
  freshInstance(true);
});

describe("/register → restore from a backup", () => {
  it("is only offered while the instance has no account", async () => {
    freshInstance(false);
    renderApp({ initialPath: "/register" });

    expect(await screen.findByRole("button", { name: /Create passkey/ })).toBeInTheDocument();
    await waitFor(() => expect(apiMock.get).toHaveBeenCalledWith("/setup"));
    expect(screen.queryByRole("button", { name: /Restore from a backup instead/ })).not.toBeInTheDocument();
  });

  it("uploads the artifact and waits for the restart", async () => {
    apiMock.upload.mockResolvedValue({ restarting: true } as never);
    await openRestore();

    fireEvent.click(screen.getByRole("button", { name: "Restore from backup" }));

    expect(await screen.findByRole("heading", { name: "Restoring…" })).toBeInTheDocument();
    const [ path, form ] = apiMock.upload.mock.calls[0];
    expect(path).toBe("/setup/restore");
    expect((form.get("artifact") as File).name).toBe("fin-20260930-120005.fogpack.tar");
    expect(form.get("confirm_identity")).toBeNull();
  });

  // A backup from another address restores, but only as a decision: its
  // passkeys won't sign in here, and the person should have a way in ready.
  it("asks for the move to be confirmed, in plain words, then restores", async () => {
    apiMock.upload
      .mockRejectedValueOnce(new Error('Artifact\'s passkeys are bound to RP ID "old.example" … or pass confirm_identity to proceed anyway'))
      .mockResolvedValueOnce({ restarting: true } as never);
    await openRestore();

    fireEvent.click(screen.getByRole("button", { name: "Restore from backup" }));

    expect(await screen.findByText(/made at a different address/)).toBeInTheDocument();
    expect(screen.queryByText(/confirm_identity/)).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: "Restore from backup" }));

    expect(await screen.findByRole("heading", { name: "Restoring…" })).toBeInTheDocument();
    expect(apiMock.upload.mock.calls[1][1].get("confirm_identity")).toBe("true");
    expect(screen.getByText(/open the sign-in link you created for this address/)).toBeInTheDocument();
  });

  it("shows any other preflight refusal as the server worded it", async () => {
    apiMock.upload.mockRejectedValue(new Error("AR_ENCRYPTION_PRIMARY_KEY differs from the one the artifact was written with"));
    await openRestore();

    fireEvent.click(screen.getByRole("button", { name: "Restore from backup" }));

    expect(await screen.findByText(/AR_ENCRYPTION_PRIMARY_KEY differs/)).toBeInTheDocument();
    expect(screen.queryByRole("checkbox")).not.toBeInTheDocument();
  });
});
