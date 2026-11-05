import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, fireEvent, waitFor, within } from "@testing-library/react";
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

const ME_PAYLOAD = {
  user: { id: "u1", email: "x@y.com", name: "X" },
  household: { id: "h1", name: "Home House", role: "admin" },
};

const HOUSEHOLDS = [
  { id: "h1", name: "Home House", role: "admin", active: true },
  { id: "h2", name: "Other House", role: "member", active: false },
];

const INVITES = [
  { code: "ABC123", role: "member", expires_at: "2026-12-31",
    accept_url: "https://fin.example/register?invite=ABC123",
    created_at: "2026-01-01T00:00:00Z", used_at: null },
];

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
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/households") return HOUSEHOLDS as never;
    if (path === "/household_memberships") return [
      { id: "mem-1", user: { id: "u1", email: "x@y.com", name: "X" }, role: "admin" },
    ] as never;
    if (path === "/invites") return INVITES as never;
    if (path === "/about") return {
      rails_version: "8.1", ruby_version: "3.2", rails_env: "test",
      git_sha: null, git_sha_short: null, hostname: "test",
    } as never;
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
});

describe("Settings → Household section", () => {
  it("renders the current household name and role", async () => {
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    // "Home House" appears in the sidebar HouseholdSwitcher AND the
    // section's "Name" row — assert at least one occurrence.
    expect((await screen.findAllByText("Home House")).length).toBeGreaterThan(0);
    expect(await screen.findByText(/Your role/i)).toBeInTheDocument();
  });

  it("admins see the Invites card with the existing invite listed", async () => {
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    expect(await screen.findByText(/Invites/i)).toBeInTheDocument();
    expect(await screen.findByText("ABC123")).toBeInTheDocument();
  });

  it("creates an invite when the form is submitted", async () => {
    apiMock.post.mockResolvedValueOnce({
      code: "NEW999", role: "member", expires_at: "2026-12-31",
      accept_url: "https://x/register?invite=NEW999",
      created_at: "2026-02-01T00:00:00Z", used_at: null,
    } as never);

    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    const createBtn = await screen.findByRole("button", { name: /Create invite/i });
    fireEvent.click(createBtn);

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/invites", { role: "member", expires_in_days: 7 });
    });
  });

  it("revokes an invite (with confirm) via DELETE /invites/:code", async () => {
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    expect(await screen.findByText("ABC123")).toBeInTheDocument();

    // The revoke button is a trash icon next to the invite row.
    fireEvent.click(screen.getAllByRole("button", { name: "Revoke invite" })[0]);

    // Confirm inside the themed dialog.
    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Revoke this invite?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Revoke" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/invites/ABC123");
    });
  });
});

// ── Gaps closed by the frontend/API interaction audit ────────────────────────

/** Members list with a second, non-admin member the current admin can act on. */
const MEMBERS = [
  { id: "mem-1", user: { id: "u1", email: "x@y.com", name: "X" }, role: "admin" },
  { id: "mem-2", user: { id: "u2", email: "partner@y.com", name: "Partner" }, role: "member" },
];

function withMembers() {
  const base = apiMock.get.getMockImplementation()!;
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/household_memberships") return MEMBERS as never;
    return base(path) as never;
  });
}

describe("Settings → Household → members", () => {
  it("promotes a member to admin via PATCH /household_memberships/:id", async () => {
    withMembers();
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    const select = await screen.findByLabelText("Role for partner@y.com");
    fireEvent.change(select, { target: { value: "admin" } });

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/household_memberships/mem-2", { role: "admin" });
    });
  });

  it("removes a member (with confirm) via DELETE /household_memberships/:id", async () => {
    withMembers();
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    expect(await screen.findByText("Partner")).toBeInTheDocument();
    fireEvent.click(screen.getByTitle("Remove"));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Remove partner@y.com?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/household_memberships/mem-2");
    });
  });

  it("does not remove the member when the confirm is declined", async () => {
    withMembers();
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    expect(await screen.findByText("Partner")).toBeInTheDocument();
    fireEvent.click(screen.getByTitle("Remove"));

    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
    expect(apiMock.delete).not.toHaveBeenCalled();
  });

  it("offers Leave rather than Remove for your own membership", async () => {
    withMembers();
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    fireEvent.click(await screen.findByTitle("Leave household"));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Leave household?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Leave" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/household_memberships/mem-1");
    });
  });
});

describe("Settings → Household → create another household", () => {
  it("creates a household via POST /households, trimming the name", async () => {
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    const input = await screen.findByLabelText("Name");
    fireEvent.change(input, { target: { value: "  Vacation Fund  " } });
    fireEvent.click(screen.getByRole("button", { name: /^Create$/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/households", { name: "Vacation Fund" });
    });
  });

  it("keeps Create disabled until a name is entered", async () => {
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    await screen.findByLabelText("Name");
    expect(screen.getByRole("button", { name: /^Create$/ })).toBeDisabled();
  });
});

describe("Settings → Household → delete household", () => {
  it("deletes via DELETE /households/:id only after the name is typed exactly", async () => {
    apiMock.delete.mockResolvedValueOnce({
      token: "new-token",
      household: { id: "h2", name: "Other House", role: "admin" },
    } as never);
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: /Delete household…/ }));

    const confirmButton = await screen.findByRole("button", { name: "Delete Home House" });
    expect(confirmButton).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText("Home House"), { target: { value: "Home Hous" } });
    expect(confirmButton).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText("Home House"), { target: { value: "Home House" } });
    expect(confirmButton).toBeEnabled();

    fireEvent.click(confirmButton);
    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/households/h1");
    });
  });

  it("surfaces the server error and keeps the dialog open when deletion fails", async () => {
    apiMock.delete.mockRejectedValueOnce(new Error("Household still has linked accounts"));
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: /Delete household…/ }));
    fireEvent.change(await screen.findByPlaceholderText("Home House"), { target: { value: "Home House" } });
    fireEvent.click(screen.getByRole("button", { name: "Delete Home House" }));

    expect(await screen.findByText("Household still has linked accounts")).toBeInTheDocument();
  });

  it("blocks deletion when it is your only household", async () => {
    const base = apiMock.get.getMockImplementation()!;
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/households") return [ HOUSEHOLDS[0] ] as never;
      return base(path) as never;
    });
    renderApp({ initialPath: "/settings#topic=household", initialToken: "tok" });

    expect(await screen.findByText(/can't delete your only household/i)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Delete household…/ })).toBeNull();
  });
});

describe("HouseholdSwitcher → POST /auth/switch_household", () => {
  it("clicking another household POSTs switch_household and clears the cache", async () => {
    apiMock.post.mockResolvedValueOnce({
      token: "new-token",
      user: ME_PAYLOAD.user,
      household: { id: "h2", name: "Other House", role: "member" },
    } as never);

    // The switcher lives in the page header (HeaderActions) — use a page
    // whose header always renders (the dashboard shows a bare welcome hero
    // when there are no transactions).
    const { client } = renderApp({ initialPath: "/transactions", initialToken: "tok" });
    const clearSpy = vi.spyOn(client, "clear");

    // Open the switcher (button labeled with the active household's name)
    const user = userEvent.setup();
    await user.click(await screen.findByRole("button", { name: /Home House/i }));

    // Pick the other household
    await user.click(await screen.findByRole("menuitem", { name: /Other House/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith(
        "/auth/switch_household",
        { household_id: "h2" },
      );
      expect(clearSpy).toHaveBeenCalled();
    });
  });

  it("hides the switcher when the user only belongs to one household", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/households") return [ HOUSEHOLDS[0] ] as never;
      return [] as never;
    });

    renderApp({ initialPath: "/transactions", initialToken: "tok" });

    // Switcher returns null with <2 households. The button labeled with the
    // active household name should NOT appear in the header.
    await waitFor(() => {
      expect(screen.queryByRole("button", { name: "Home House" })).toBeNull();
    });
  });
});
