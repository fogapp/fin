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

import { api, clearToken } from "@/api/client";
import { renderApp } from "@/test/renderApp";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x@y.com", name: "X" },
  household: { id: "h1", name: "Home House", role: "admin" },
};

const BROKERS = [
  { id: "b1", name: "Fidelity", account_count: 2 },
  { id: "b2", name: "Vanguard", account_count: 0 },
];

const CREDS = [
  { id: "c1", nickname: "MacBook Pro", created_at: "2026-01-05T00:00:00Z", last_used_at: "2026-06-01T00:00:00Z" },
  { id: "c2", nickname: null, created_at: "2026-02-10T00:00:00Z", last_used_at: null },
];

const ISSUES = [
  { id: "i1", title: "Stale account balance", body: "Account X has not synced in 30 days.",
    severity: "error", source: "audit/balances", dismissed_at: null,
    created_at: "2026-06-20T00:00:00Z" },
  { id: "i2", title: "Uncategorized merchants", body: null,
    severity: "warning", source: null, dismissed_at: null,
    created_at: "2026-06-21T00:00:00Z" },
];

const API_TOKENS = [
  { id: "t1", name: "CI pipeline", last_used_at: null, expires_at: null,
    created_at: "2026-01-01T00:00:00Z" },
];

const seededWorkflow = (over: Record<string, unknown>) => ({
  description: null, trigger_type: "schedule", trigger_config: { frequency: "daily", at: "05:00" },
  active: true, position: 0, next_scheduled_at: null, schedule_summary: "daily at 05:00",
  created_at: "2026-06-01T00:00:00Z", updated_at: "2026-06-01T00:00:00Z",
  run_count: 0, last_run_status: null, last_run_at: null,
  ...over,
});

const SEEDED_WORKFLOWS = [
  seededWorkflow({ id: "wsys",  name: "System audit",       seed_key: "system_audit",       schedule_summary: "daily at 03:00" }),
  seededWorkflow({ id: "wmkt",  name: "Market data sync",   seed_key: "market_data_sync" }),
  seededWorkflow({ id: "wnews", name: "Security news sync", seed_key: "security_news_sync", schedule_summary: "every 6 hours", active: false }),
];

const PLAID_UNCONFIGURED = {
  environment: "production", client_id_set: false, secret_set: false,
  configured: false, source: "environment",
};
const COINBASE_UNCONFIGURED = { api_key_id_set: false, api_key_secret_set: false, configured: false };
const CMC_UNCONFIGURED = { api_key_set: false, configured: false };

/** Default GET routing; individual tests override paths they care about. */
function installGetStub(overrides: Record<string, unknown> = {}) {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path in overrides) return overrides[path] as never;
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/brokers") return BROKERS as never;
    if (path === "/webauthn_credentials") return CREDS as never;
    if (path === "/issues") return ISSUES as never;
    if (path === "/api_tokens") return API_TOKENS as never;
    if (path === "/plaid/configuration") return PLAID_UNCONFIGURED as never;
    if (path === "/coinbase/configuration") return COINBASE_UNCONFIGURED as never;
    if (path === "/coin_market_cap/configuration") return CMC_UNCONFIGURED as never;
    return [] as never;
  });
}

beforeEach(() => {
  clearToken();
  sessionStorage.clear();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  apiMock.post.mockResolvedValue({} as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  installGetStub();
});

// ── Brokers ───────────────────────────────────────────────────────────────────

describe("Settings → Brokers section", () => {
  it("lists brokers with their account counts", async () => {
    renderApp({ initialPath: "/settings#topic=brokers", initialToken: "tok" });

    expect(await screen.findByText("Fidelity")).toBeInTheDocument();
    expect(screen.getByText("Vanguard")).toBeInTheDocument();
    expect(screen.getByText("2 accounts")).toBeInTheDocument();
    expect(screen.getByText("0 accounts")).toBeInTheDocument();
  });

  it("adds a broker via POST /brokers", async () => {
    renderApp({ initialPath: "/settings#topic=brokers", initialToken: "tok" });

    const input = await screen.findByPlaceholderText(/Fidelity, Vanguard, Chase/);
    fireEvent.change(input, { target: { value: "Schwab" } });
    fireEvent.click(screen.getByRole("button", { name: /Add broker/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/brokers", { name: "Schwab" });
    });
  });

  it("deletes an empty broker (with confirm) and disables delete for brokers with accounts", async () => {
    renderApp({ initialPath: "/settings#topic=brokers", initialToken: "tok" });

    expect(await screen.findByText("Vanguard")).toBeInTheDocument();

    // Fidelity has 2 accounts → its delete button is disabled with a hint title.
    expect(screen.getByTitle("Has accounts — delete those first")).toBeDisabled();

    // Vanguard has 0 accounts → deletable, behind the confirm dialog.
    fireEvent.click(screen.getByTitle("Delete"));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Delete Vanguard?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Delete" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/brokers/b2");
    });
  });
});

// ── Devices ───────────────────────────────────────────────────────────────────

describe("Settings → Devices section", () => {
  it("lists registered passkeys, showing nicknames and an Unnamed fallback", async () => {
    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    expect(await screen.findByText("Registered passkeys")).toBeInTheDocument();
    expect(await screen.findByText("MacBook Pro")).toBeInTheDocument();
    expect(screen.getByText("Unnamed device")).toBeInTheDocument();
  });

  it("removes a passkey via DELETE /webauthn_credentials/:id", async () => {
    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    expect(await screen.findByText("MacBook Pro")).toBeInTheDocument();

    const removeButtons = screen.getAllByTitle("Remove");
    expect(removeButtons).toHaveLength(2);
    fireEvent.click(removeButtons[0]);

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/webauthn_credentials/c1");
    });
  });

  it("generates a device invite link via POST /device_invites and shows the join URL", async () => {
    apiMock.post.mockResolvedValueOnce({
      token: "inv-tok-123",
      expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    } as never);

    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: /Generate invite link/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/device_invites", {});
    });
    expect(await screen.findByText("Device invite link")).toBeInTheDocument();
    expect(screen.getByText(/\/join-device\?token=inv-tok-123/)).toBeInTheDocument();

    // Dismiss hides the invite and restores the generate button.
    fireEvent.click(screen.getByRole("button", { name: "Dismiss" }));
    expect(await screen.findByRole("button", { name: /Generate invite link/i })).toBeInTheDocument();
  });
});

// ── Issues ────────────────────────────────────────────────────────────────────

describe("Settings → Issues section", () => {
  it("lists issues with severity icons, body, source chip, and a nav count badge", async () => {
    const { container } = renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

    expect(await screen.findByText("Stale account balance")).toBeInTheDocument();
    expect(screen.getByText("Account X has not synced in 30 days.")).toBeInTheDocument();
    expect(screen.getByText("audit/balances")).toBeInTheDocument();
    expect(screen.getByText("Uncategorized merchants")).toBeInTheDocument();
    // Sidebar nav label shows the active-issue count.
    expect(screen.getByRole("button", { name: /Issues\s?2/ })).toBeInTheDocument();
    // error → destructive icon; warning → amber icon (lucide class names vary
    // by version, so match on the color classes the component applies).
    expect(container.querySelector("svg.text-destructive.shrink-0")).not.toBeNull();
    expect(container.querySelector("svg.text-warning")).not.toBeNull();
  });

  describe("a suggested security conversion", () => {
    const CONVERSION_ISSUE = {
      id: "i9", key: "security_conversion:sc1",
      title: "Possible conversion: SMNEY → SMERY in Global (Jan 30, 2026)",
      body: "SMNEY stopped trading after 2026-01-29 …", severity: "warning", source: "system_audit",
      dismissed_at: null, created_at: "2026-09-25T00:00:00Z",
    };

    it("confirms it via POST /security_conversions/:id/confirm", async () => {
      installGetStub({ "/issues": [CONVERSION_ISSUE] });
      renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

      fireEvent.click(await screen.findByRole("button", { name: /Confirm conversion/ }));

      await waitFor(() => {
        expect(apiMock.post).toHaveBeenCalledWith("/security_conversions/sc1/confirm", {});
      });
    });

    it("dismisses it via POST /security_conversions/:id/dismiss", async () => {
      installGetStub({ "/issues": [CONVERSION_ISSUE] });
      renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

      fireEvent.click(await screen.findByRole("button", { name: /Not a conversion/ }));

      await waitFor(() => {
        expect(apiMock.post).toHaveBeenCalledWith("/security_conversions/sc1/dismiss", {});
      });
    });

    it("offers no conversion actions on ordinary issues", async () => {
      renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

      expect(await screen.findByText("Stale account balance")).toBeInTheDocument();
      expect(screen.queryByRole("button", { name: /Confirm conversion/ })).toBeNull();
    });
  });

  it("dismisses an issue via DELETE /issues/:id", async () => {
    renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

    expect(await screen.findByText("Stale account balance")).toBeInTheDocument();

    fireEvent.click(screen.getAllByTitle("Dismiss")[0]);

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/issues/i1");
    });
  });

  it("clears all issues via POST /issues/dismiss_all after a confirm, showing the count", async () => {
    apiMock.post.mockResolvedValue({ dismissed: 2 } as never);

    renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

    expect(await screen.findByText("Stale account balance")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Clear all/ }));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Dismiss all 2 open issues?")).toBeInTheDocument();
    expect(within(dialog).getByText(/will reappear on the next audit/)).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Dismiss all" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/issues/dismiss_all", {});
    });
    expect(await screen.findByText("2 dismissed")).toBeInTheDocument();
  });

  it("does not clear issues when the confirm is dismissed", async () => {
    renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

    expect(await screen.findByText("Stale account balance")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Clear all/ }));

    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => {
      expect(screen.queryByRole("alertdialog")).toBeNull();
    });
    expect(apiMock.post).not.toHaveBeenCalledWith("/issues/dismiss_all", {});
  });

  it("shows the empty state and queues the system-audit workflow via run_now", async () => {
    installGetStub({ "/issues": [], "/workflows": SEEDED_WORKFLOWS });

    renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

    expect(await screen.findByText(/No active issues — everything looks good/)).toBeInTheDocument();

    const button = screen.getByRole("button", { name: /Run audit/i });
    await waitFor(() => expect(button).toBeEnabled());
    fireEvent.click(button);

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows/wsys/run_now", {});
    });
    expect(await screen.findByText("Queued")).toBeInTheDocument();
  });

  it("disables Run audit with a hint when the system_audit workflow is missing", async () => {
    installGetStub({ "/issues": [], "/workflows": [] });

    renderApp({ initialPath: "/settings#topic=issues", initialToken: "tok" });

    expect(await screen.findByText(/No active issues — everything looks good/)).toBeInTheDocument();
    const button = screen.getByRole("button", { name: /Run audit/i });
    expect(button).toBeDisabled();
    expect(button).toHaveAttribute("title", "System audit workflow not found");
  });
});

// ── Market (seeded sync workflows) ────────────────────────────────────────────

describe("Settings → Market section", () => {
  it("lists the seeded market sync workflows with schedule and edit links", async () => {
    installGetStub({ "/workflows": SEEDED_WORKFLOWS });

    renderApp({ initialPath: "/settings#topic=market", initialToken: "tok" });

    expect(await screen.findByText("Market data sync")).toBeInTheDocument();
    expect(screen.getByText("Security news sync")).toBeInTheDocument();
    // System audit isn't a market seed and stays out of this card.
    expect(screen.queryByText("System audit")).not.toBeInTheDocument();

    expect(screen.getByText("daily at 05:00")).toBeInTheDocument();
    expect(screen.getByText("every 6 hours")).toBeInTheDocument();

    const links = screen.getAllByRole("link", { name: "Edit schedule" });
    expect(links.map((l) => l.getAttribute("href"))).toEqual(["/workflows/wmkt", "/workflows/wnews"]);
  });
});

// ── Scheduled jobs note ───────────────────────────────────────────────────────


// ── Activity link-out topic ───────────────────────────────────────────────────

describe("Settings → Activity topic", () => {
  it("navigates to the full /activity page", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/issues") return [] as never;
      if (path === "/system_health") return {
        workflows: { failed_7d: 0 }, errors_24h: 0,
        sources: [], market_data: { open_drift_findings: 0, stale_held_instruments: 0, providers: [] },
      } as never;
      if (path.startsWith("/activity?")) return { groups: [], meta: { page: 1, per_page: 30, total: 0 } } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/settings", initialToken: "tok" });

    fireEvent.click(await screen.findByRole("button", { name: /Activity/ }));

    expect(await screen.findByRole("heading", { name: "Activity" })).toBeInTheDocument();
  });
});

// ── API Tokens ────────────────────────────────────────────────────────────────

describe("Settings → API Tokens section", () => {
  it("lists tokens and deletes one (with confirm) via DELETE /api_tokens/:id", async () => {
    renderApp({ initialPath: "/settings#topic=tokens", initialToken: "tok" });

    expect(await screen.findByText("CI pipeline")).toBeInTheDocument();
    // Never used and never expires.
    expect(screen.getAllByText("Never").length).toBeGreaterThanOrEqual(2);

    const trashButtons = screen.getAllByRole("button").filter((b) =>
      b.querySelector("svg.lucide-trash-2"),
    );
    expect(trashButtons.length).toBeGreaterThanOrEqual(1);
    fireEvent.click(trashButtons[0]);

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText('Delete token "CI pipeline"?')).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Delete" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/api_tokens/t1");
    });
  });
});

// ── Integrations ──────────────────────────────────────────────────────────────

describe("Settings → Integrations section", () => {
  it("shows the empty state when no provider is configured", async () => {
    renderApp({ initialPath: "/settings#topic=integrations", initialToken: "tok" });

    expect(await screen.findByText("No connections yet")).toBeInTheDocument();
    expect(screen.getByText("Add your first connection")).toBeInTheDocument();
    expect(screen.queryByText("Plaid")).toBeNull();
  });

  it("lists a configured Plaid connection", async () => {
    installGetStub({
      "/plaid/configuration": {
        environment: "production", client_id_set: true, secret_set: true,
        configured: true, source: "database",
      },
    });

    renderApp({ initialPath: "/settings#topic=integrations", initialToken: "tok" });

    expect(await screen.findByText("Plaid")).toBeInTheDocument();
    expect(screen.getByText(/Bank & investment accounts/)).toBeInTheDocument();
    expect(screen.getByText("Select a connection to view details")).toBeInTheDocument();
    expect(screen.queryByText("Coinbase")).toBeNull();
  });
});

// ── Gaps closed by the frontend/API interaction audit ─────────────────────────

describe("Settings → Brokers section → rename", () => {
  it("renames a broker via PATCH /brokers/:id, trimming the name", async () => {
    renderApp({ initialPath: "/settings#topic=brokers", initialToken: "tok" });

    expect(await screen.findByText("Vanguard")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[1]);

    const input = screen.getAllByLabelText("Broker name").find((el) => (el as HTMLInputElement).value === "Vanguard")!;
    fireEvent.change(input, { target: { value: "  Vanguard Brokerage  " } });
    fireEvent.click(screen.getByTitle("Save"));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/brokers/b2", { name: "Vanguard Brokerage" });
    });
  });

  it("submits the rename on Enter", async () => {
    renderApp({ initialPath: "/settings#topic=brokers", initialToken: "tok" });

    expect(await screen.findByText("Vanguard")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[1]);

    const input = screen.getAllByLabelText("Broker name").find((el) => (el as HTMLInputElement).value === "Vanguard")!;
    fireEvent.change(input, { target: { value: "Renamed" } });
    fireEvent.keyDown(input, { key: "Enter" });

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/brokers/b2", { name: "Renamed" });
    });
  });

  it("surfaces the server's error message when the rename is rejected", async () => {
    apiMock.patch.mockRejectedValueOnce(new Error("Name has already been taken"));
    renderApp({ initialPath: "/settings#topic=brokers", initialToken: "tok" });

    expect(await screen.findByText("Vanguard")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[1]);

    fireEvent.change(screen.getAllByLabelText("Broker name").find((el) => (el as HTMLInputElement).value === "Vanguard")!, { target: { value: "Fidelity" } });
    fireEvent.click(screen.getByTitle("Save"));

    expect(await screen.findByText("Name has already been taken")).toBeInTheDocument();
  });

  it("does not send an empty name", async () => {
    renderApp({ initialPath: "/settings#topic=brokers", initialToken: "tok" });

    expect(await screen.findByText("Vanguard")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[1]);

    fireEvent.change(screen.getAllByLabelText("Broker name").find((el) => (el as HTMLInputElement).value === "Vanguard")!, { target: { value: "   " } });
    expect(screen.getByTitle("Save")).toBeDisabled();
    expect(apiMock.patch).not.toHaveBeenCalled();
  });
});

describe("Settings → Devices section → rename", () => {
  it("renames a passkey via PATCH /webauthn_credentials/:id", async () => {
    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    expect(await screen.findByText("MacBook Pro")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[0]);

    const input = await screen.findByLabelText("Device name");
    expect(input).toHaveValue("MacBook Pro");
    fireEvent.change(input, { target: { value: "Work laptop" } });
    fireEvent.click(screen.getByText("Save"));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/webauthn_credentials/c1", { nickname: "Work laptop" });
    });
  });

  it("seeds the rename field with an empty value for an unnamed passkey", async () => {
    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    expect(await screen.findByText("Unnamed device")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[1]);

    expect(await screen.findByLabelText("Device name")).toHaveValue("");
  });

  it("blocks clearing a nickname: Save is disabled and nothing is sent", async () => {
    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    expect(await screen.findByText("MacBook Pro")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[0]);

    const input = await screen.findByLabelText("Device name");
    fireEvent.change(input, { target: { value: "   " } });

    expect(screen.getByText("Save")).toBeDisabled();
    expect(await screen.findByText(/A passkey needs a name/i)).toBeInTheDocument();
    expect(apiMock.patch).not.toHaveBeenCalled();
  });

  it("re-enables Save once a real name is typed again", async () => {
    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    expect(await screen.findByText("MacBook Pro")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[0]);

    const input = await screen.findByLabelText("Device name");
    fireEvent.change(input, { target: { value: "" } });
    expect(screen.getByText("Save")).toBeDisabled();

    fireEvent.change(input, { target: { value: "Studio Mac" } });
    expect(screen.getByText("Save")).toBeEnabled();
    expect(screen.queryByText(/A passkey needs a name/i)).toBeNull();
  });

  it("surfaces the server's message if a rename is rejected", async () => {
    apiMock.patch.mockRejectedValueOnce(new Error("Nickname can't be blank"));
    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    expect(await screen.findByText("MacBook Pro")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[0]);

    fireEvent.change(await screen.findByLabelText("Device name"), { target: { value: "Studio Mac" } });
    fireEvent.click(screen.getByText("Save"));

    expect(await screen.findByText("Nickname can't be blank")).toBeInTheDocument();
    // Still in edit mode, so the failure is recoverable rather than silent.
    expect(screen.getByLabelText("Device name")).toBeInTheDocument();
  });

  it("cancels a rename without sending anything", async () => {
    renderApp({ initialPath: "/settings#topic=devices", initialToken: "tok" });

    expect(await screen.findByText("MacBook Pro")).toBeInTheDocument();
    fireEvent.click(screen.getAllByTitle("Rename")[0]);

    fireEvent.change(await screen.findByLabelText("Device name"), { target: { value: "Nope" } });
    fireEvent.click(screen.getByText("Cancel"));

    await waitFor(() => expect(screen.queryByLabelText("Device name")).toBeNull());
    expect(apiMock.patch).not.toHaveBeenCalled();
  });
});

describe("Settings → API Tokens section → create", () => {
  it("creates a token via POST /api_tokens and reveals the raw value once", async () => {
    apiMock.post.mockResolvedValueOnce({
      id: "t2", name: "Deploy bot", token: "fin_pat_supersecret",
    } as never);
    renderApp({ initialPath: "/settings#topic=tokens", initialToken: "tok" });

    fireEvent.click(await screen.findByText("New token"));
    fireEvent.change(await screen.findByPlaceholderText(/CI pipeline, local dev/), { target: { value: "Deploy bot" } });
    fireEvent.click(screen.getByText("Create token"));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/api_tokens", {
        name: "Deploy bot", expires_at: null,
      });
    });

    expect(await screen.findByText("fin_pat_supersecret")).toBeInTheDocument();
    expect(screen.getByText(/won't be shown again/i)).toBeInTheDocument();
  });

  it("sends the expiry when one is picked", async () => {
    apiMock.post.mockResolvedValueOnce({ id: "t2", name: "Temp", token: "tok_x" } as never);
    renderApp({ initialPath: "/settings#topic=tokens", initialToken: "tok" });

    fireEvent.click(await screen.findByText("New token"));
    fireEvent.change(await screen.findByPlaceholderText(/CI pipeline, local dev/), { target: { value: "Temp" } });
    fireEvent.change(document.getElementById("api-token-expires")!, { target: { value: "2026-12-31" } });
    fireEvent.click(screen.getByText("Create token"));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/api_tokens", {
        name: "Temp", expires_at: "2026-12-31",
      });
    });
  });

  it("sends a null name when the optional field is left blank", async () => {
    apiMock.post.mockResolvedValueOnce({ id: "t2", name: null, token: "tok_y" } as never);
    renderApp({ initialPath: "/settings#topic=tokens", initialToken: "tok" });

    fireEvent.click(await screen.findByText("New token"));
    fireEvent.click(await screen.findByText("Create token"));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/api_tokens", { name: null, expires_at: null });
    });
  });

  it("shows an error and keeps the form open when creation fails", async () => {
    apiMock.post.mockRejectedValueOnce(new Error("Internal server error"));
    renderApp({ initialPath: "/settings#topic=tokens", initialToken: "tok" });

    fireEvent.click(await screen.findByText("New token"));
    fireEvent.change(await screen.findByPlaceholderText(/CI pipeline, local dev/), { target: { value: "Boom" } });
    fireEvent.click(screen.getByText("Create token"));

    expect(await screen.findByText(/Failed to create token/i)).toBeInTheDocument();
    expect(screen.getByText("Create token")).toBeInTheDocument();
  });
});


describe("Settings → Merchants section", () => {
  const MERCHANTS = [
    { id: "m1", name: "Starbucks", transaction_count: 42, category_name: "Coffee", excluded: false },
    { id: "m2", name: "Venmo",     transaction_count: 8,  category_name: null,     excluded: true },
  ];

  function withMerchants() {
    installGetStub({ "/merchants": MERCHANTS });
  }

  it("excludes a merchant via POST /merchants/:id/exclude", async () => {
    withMerchants();
    renderApp({ initialPath: "/settings#topic=merchants", initialToken: "tok" });

    expect(await screen.findByText("Starbucks")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Exclude/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/merchants/m1/exclude", {});
    });
  });

  it("re-includes an excluded merchant via POST /merchants/:id/include", async () => {
    withMerchants();
    renderApp({ initialPath: "/settings#topic=merchants", initialToken: "tok" });

    expect(await screen.findByText("Excluded (1)")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Remove/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/merchants/m2/include", {});
    });
  });

  it("filters the active list and leaves excluded merchants out of it", async () => {
    withMerchants();
    renderApp({ initialPath: "/settings#topic=merchants", initialToken: "tok" });

    const search = await screen.findByLabelText("Search merchants");
    fireEvent.change(search, { target: { value: "zzz" } });

    expect(await screen.findByText("No merchants match your search.")).toBeInTheDocument();
    // The excluded card is not affected by the search box.
    expect(screen.getByText("Excluded (1)")).toBeInTheDocument();
  });
});

// ── Transactions → description search ─────────────────────────────────────────

describe("Settings → Transactions section", () => {
  it("picks the search engine the detail pane links descriptions to", async () => {
    localStorage.setItem("prefs-migrated-v1", "1"); // skip the one-time LS → server migration
    renderApp({ initialPath: "/settings#topic=transactions", initialToken: "tok" });

    const tablist = await screen.findByRole("tablist", { name: "Search engine" });
    expect(within(tablist).getByRole("tab", { name: "Google" })).toHaveAttribute("aria-selected", "true");

    fireEvent.click(within(tablist).getByRole("tab", { name: "Brave" }));

    await waitFor(() =>
      expect(within(tablist).getByRole("tab", { name: "Brave" })).toHaveAttribute("aria-selected", "true"));
    // The write itself is debounced, so it lands a moment after the click.
    await waitFor(
      () => expect(apiMock.patch).toHaveBeenCalledWith("/preferences", {
        data: { transactions: { search_engine: "brave" } },
      }),
      { timeout: 2000 },
    );
  });
});

// ── Timeframes ────────────────────────────────────────────────────────────────

describe("Settings → Timeframes section", () => {
  const DEFAULT_BUTTONS = ["mtd", "last_month", "3m", "6m", "1y", "ytd", "all"]
    .map((key) => ({ type: "builtin", key }));

  beforeEach(() => {
    localStorage.setItem("prefs-migrated-v1", "1"); // skip the one-time LS → server migration
  });

  /** The debounced preferences write carrying the timeframe settings. */
  async function expectSaved(timeframes: unknown) {
    await waitFor(
      () => expect(apiMock.patch).toHaveBeenCalledWith("/preferences", { data: { timeframes } }),
      { timeout: 2000 },
    );
  }

  async function open() {
    renderApp({ initialPath: "/settings#topic=timeframes", initialToken: "tok" });
    await screen.findByRole("heading", { name: "Timeframe buttons" });
  }

  it("lists the default row and each page's default", async () => {
    await open();

    expect(screen.getByText("Month to date")).toBeInTheDocument();
    expect(screen.getByText("Last complete month")).toBeInTheDocument();
    expect(screen.getByLabelText("Cashflow")).toHaveValue("1y");
    expect(screen.getByLabelText("Net Worth")).toHaveValue("1y");
    expect(screen.getByLabelText("Investments")).toHaveValue("all");
    // Nothing customized yet, so there's nothing to reset.
    expect(screen.queryByRole("button", { name: "Reset to defaults" })).toBeNull();
  });

  it("adds a built-in preset such as last calendar year", async () => {
    await open();

    fireEvent.change(screen.getByLabelText("Preset"), { target: { value: "last_year" } });
    fireEvent.click(screen.getByRole("button", { name: "Add button" }));

    await expectSaved({ buttons: [...DEFAULT_BUTTONS, { type: "builtin", key: "last_year" }], defaults: {} });
    expect(await screen.findByText("Last calendar year")).toBeInTheDocument();
  });

  it("adds a rolling window with a suggested label", async () => {
    await open();

    fireEvent.click(screen.getByRole("tab", { name: "Last N…" }));
    fireEvent.change(screen.getByLabelText("Last"), { target: { value: "2" } });
    fireEvent.change(screen.getByLabelText("Unit"), { target: { value: "years" } });
    expect(screen.getByLabelText("Button label")).toHaveAttribute("placeholder", "2Y");
    fireEvent.click(screen.getByRole("button", { name: "Add button" }));

    await expectSaved({
      buttons: [...DEFAULT_BUTTONS, { type: "rolling", id: expect.any(String), label: "2Y", amount: 2, unit: "years" }],
      defaults: {},
    });
  });

  it("adds a fixed date range under a custom label", async () => {
    await open();

    fireEvent.click(screen.getByRole("tab", { name: "Date range" }));
    fireEvent.change(screen.getByLabelText("From"), { target: { value: "2023-10-01" } });
    fireEvent.change(screen.getByLabelText("To"), { target: { value: "2024-09-30" } });
    fireEvent.change(screen.getByLabelText("Button label"), { target: { value: "FY24" } });
    fireEvent.click(screen.getByRole("button", { name: "Add button" }));

    await expectSaved({
      buttons: [...DEFAULT_BUTTONS, { type: "fixed", id: expect.any(String), label: "FY24", from: "2023-10-01", to: "2024-09-30" }],
      defaults: {},
    });
  });

  it("removes and reorders buttons, and sets a page's default", async () => {
    await open();

    fireEvent.click(screen.getByRole("button", { name: "Remove 6M" }));
    const withoutSixMonths = DEFAULT_BUTTONS.filter((b) => b.key !== "6m");
    await expectSaved({ buttons: withoutSixMonths, defaults: {} });

    fireEvent.click(screen.getByRole("button", { name: "Move MTD down" }));
    const [first, second, ...rest] = withoutSixMonths;
    await expectSaved({ buttons: [second, first, ...rest], defaults: {} });

    fireEvent.change(screen.getByLabelText("Net Worth"), { target: { value: "ytd" } });
    await expectSaved({ buttons: [second, first, ...rest], defaults: { net_worth: "ytd" } });

    fireEvent.click(screen.getByRole("button", { name: "Reset to defaults" }));
    await expectSaved(null);
  });

  it("falls back to the page's built-in default when its chosen button is removed", async () => {
    installGetStub({
      "/preferences": { data: { timeframes: { buttons: DEFAULT_BUTTONS, defaults: { cashflow: "mtd" } } } },
    });
    await open();
    await waitFor(() => expect(screen.getByLabelText("Cashflow")).toHaveValue("mtd"));

    fireEvent.click(screen.getByRole("button", { name: "Remove MTD" }));
    await waitFor(() => expect(screen.getByLabelText("Cashflow")).toHaveValue("1y"));
  });

  it("won't remove the last button", async () => {
    installGetStub({
      "/preferences": { data: { timeframes: { buttons: [{ type: "builtin", key: "mtd" }] } } },
    });
    await open();

    // The saved one-button row replaces the defaults once preferences load.
    await waitFor(() => expect(screen.queryByText("Last 12 months")).toBeNull());
    expect(screen.getByRole("button", { name: "Remove MTD" })).toBeDisabled();
  });
});
