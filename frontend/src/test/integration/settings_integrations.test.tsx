import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, fireEvent, waitFor, within } from "@testing-library/react";

vi.mock("@simplewebauthn/browser", () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

vi.mock("react-plaid-link", () => ({
  usePlaidLink: () => ({ open: vi.fn(), ready: false }),
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

const PLAID_UNCONFIGURED = {
  environment: "production", client_id_set: false, secret_set: false,
  configured: false, source: "environment",
};
const PLAID_CONFIGURED = {
  environment: "production", client_id_set: true, secret_set: true,
  configured: true, source: "database",
};
const COINBASE_UNCONFIGURED = { api_key_id_set: false, api_key_secret_set: false, configured: false };
const COINBASE_CONFIGURED = { api_key_id_set: true, api_key_secret_set: true, configured: true };
const CMC_UNCONFIGURED = { api_key_set: false, configured: false };
const CMC_CONFIGURED = { api_key_set: true, configured: true };

const PLAID_ITEMS = [
  {
    id: "pi1", institution_name: "Chase", institution_id: "ins_1", status: "active",
    last_synced_at: "2026-06-25T12:00:00Z",
    plaid_accounts: [
      {
        id: "pa1", name: "Checking", display_name: "Chase Checking", mask: "1234",
        account_type: "depository", account_subtype: "checking", linked: true,
        account_id: "a1", bank_count: 42, credit_card_count: 0,
      },
      {
        id: "pa2", name: "Savings", display_name: "Chase Savings", mask: "5678",
        account_type: "depository", account_subtype: "savings", linked: false,
        account_id: null, bank_count: 0, credit_card_count: 0,
      },
    ],
  },
  {
    id: "pi2", institution_name: "Charles Schwab", institution_id: "ins_2", status: "error",
    last_synced_at: null, plaid_accounts: [],
  },
];

const COINBASE_ACCOUNTS = [
  { id: "ca1", name: "ETH Wallet", currency: "ETH", balance: "2", type: "wallet", balance_usd: 5000 },
  { id: "ca2", name: "BTC Wallet", currency: "BTC", balance: "0.5", type: "wallet", balance_usd: 30000 },
  { id: "ca3", name: "SOL Wallet", currency: "SOL", balance: "0", type: "wallet", balance_usd: 0 },
  { id: "ca4", name: "USDC Wallet", currency: "USDC", balance: null, type: "wallet", balance_usd: null },
];

/** Default GET routing; individual tests override paths they care about. */
function installGetStub(overrides: Record<string, unknown> = {}) {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path in overrides) return overrides[path] as never;
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/plaid/configuration") return PLAID_UNCONFIGURED as never;
    if (path === "/coinbase/configuration") return COINBASE_UNCONFIGURED as never;
    if (path === "/coin_market_cap/configuration") return CMC_UNCONFIGURED as never;
    return [] as never;
  });
}

function renderIntegrations() {
  return renderApp({ initialPath: "/settings#topic=integrations", initialToken: "tok" });
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

// ── Add-connection flow ───────────────────────────────────────────────────────

describe("Settings → Integrations → Add connection", () => {
  it("shows the provider picker and navigates into and back out of a provider form", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));

    expect(await screen.findByText("Add connection")).toBeInTheDocument();
    expect(screen.getByText("Plaid")).toBeInTheDocument();
    expect(screen.getByText("Coinbase")).toBeInTheDocument();
    expect(screen.getByText("CoinMarketCap")).toBeInTheDocument();
    expect(screen.getByText(/Connect banks, credit cards, and investment accounts/)).toBeInTheDocument();

    // Into the Coinbase form…
    fireEvent.click(screen.getByText("Coinbase"));
    expect(await screen.findByText("Connect Coinbase")).toBeInTheDocument();
    expect(screen.getByText(/Advanced Trade API credentials to sync crypto/)).toBeInTheDocument();

    // …and back to the picker.
    fireEvent.click(screen.getByText("All providers"));
    expect(await screen.findByText("Add connection")).toBeInTheDocument();
  });

  it("submits new Plaid credentials, omitting blank fields from the PATCH", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("Plaid"));

    expect(await screen.findByText("Connect Plaid")).toBeInTheDocument();
    // Unconfigured credentials fall back to env variables.
    expect(screen.getAllByText("Using env variable")).toHaveLength(2);

    // Leaving both fields blank submits only the environment.
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "sandbox" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/plaid/configuration", {
        plaid_configuration: { environment: "sandbox" },
      });
    });
  });

  it("submits Coinbase API credentials via PATCH /coinbase/configuration", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("Coinbase"));

    // Unconfigured key + secret indicators.
    expect(await screen.findAllByText("Not set")).toHaveLength(2);

    fireEvent.change(screen.getByPlaceholderText("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"), {
      target: { value: "key-id-1" },
    });
    fireEvent.change(screen.getByPlaceholderText("Paste your secret"), {
      target: { value: "sekret-1" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/coinbase/configuration", {
        coinbase_configuration: { api_key_id: "key-id-1", api_key_secret: "sekret-1" },
      });
    });
  });

  it("disables the CoinMarketCap save button until a key is entered, then PATCHes it", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("CoinMarketCap"));

    expect(await screen.findByText("Connect CoinMarketCap")).toBeInTheDocument();
    expect(screen.getByText("Not set")).toBeInTheDocument();

    // No key configured and none typed → cannot save.
    const save = screen.getByRole("button", { name: "Save" });
    expect(save).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText("Enter your CoinMarketCap API key"), {
      target: { value: "cmc-key-1" },
    });
    expect(save).toBeEnabled();
    fireEvent.click(save);

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/coin_market_cap/configuration", {
        coin_market_cap_configuration: { api_key: "cmc-key-1" },
      });
    });
  });
});

// ── Plaid detail panel ────────────────────────────────────────────────────────

describe("Settings → Integrations → Plaid detail", () => {
  beforeEach(() => {
    installGetStub({
      "/plaid/configuration": PLAID_CONFIGURED,
      "/plaid/items": PLAID_ITEMS,
    });
  });

  it("shows the banner, account total, and institutions with status and sync info", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Plaid"));

    // Healthy institution (await the items query before asserting totals).
    expect(await screen.findByText("Chase")).toBeInTheDocument();
    expect(screen.getByText("Connected institutions")).toBeInTheDocument();
    expect(screen.getByText("Connected")).toBeInTheDocument();
    expect(screen.getByText("production")).toBeInTheDocument();
    // Two Plaid accounts across both items.
    expect(screen.getByText("2", { selector: ".text-4xl" })).toBeInTheDocument();
    expect(screen.getByText("accounts")).toBeInTheDocument();

    expect(screen.getByText("active")).toBeInTheDocument();
    expect(screen.getByText(/Last synced: Jun 2[456], 2026/)).toBeInTheDocument();

    // Errored institution that has never synced.
    expect(screen.getByText("Charles Schwab")).toBeInTheDocument();
    expect(screen.getByText("error")).toBeInTheDocument();
    expect(screen.getByText("Last synced: Never")).toBeInTheDocument();

    // Account rows: name, type, and linked state.
    expect(screen.getByText("Chase Checking")).toBeInTheDocument();
    expect(screen.getByText("Linked")).toBeInTheDocument();
    expect(screen.getByText("Chase Savings")).toBeInTheDocument();
    expect(screen.getByText("Unlinked")).toBeInTheDocument();

    // History-backfill hint shows when institutions exist.
    expect(screen.getByText(/Transaction history on first connect is limited/)).toBeInTheDocument();
  });

  it("shows the no-institutions empty state", async () => {
    installGetStub({
      "/plaid/configuration": PLAID_CONFIGURED,
      "/plaid/items": [],
    });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Plaid"));

    expect(await screen.findByText(/No institutions connected yet/)).toBeInTheDocument();
    expect(screen.getByText("0", { selector: ".text-4xl" })).toBeInTheDocument();
  });

  it("syncs an institution via POST /plaid/items/:id/sync", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Plaid"));

    const syncButtons = await screen.findAllByRole("button", { name: "Sync" });
    expect(syncButtons).toHaveLength(2);
    fireEvent.click(syncButtons[0]);

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/plaid/items/pi1/sync");
    });
  });

  it("disconnects an institution (with confirm) via DELETE /plaid/items/:id", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Plaid"));
    expect(await screen.findByText("Chase")).toBeInTheDocument();

    const unlinkButtons = screen.getAllByRole("button").filter((b) =>
      b.querySelector("svg.lucide-unlink"),
    );
    expect(unlinkButtons).toHaveLength(2);
    fireEvent.click(unlinkButtons[0]);

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Disconnect Chase?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Disconnect" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/plaid/items/pi1");
    });
  });

  it("does not disconnect when the confirm dialog is declined", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Plaid"));
    expect(await screen.findByText("Chase")).toBeInTheDocument();

    const unlinkButtons = screen.getAllByRole("button").filter((b) =>
      b.querySelector("svg.lucide-unlink"),
    );
    fireEvent.click(unlinkButtons[0]);

    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => {
      expect(screen.queryByRole("alertdialog")).toBeNull();
    });
    expect(apiMock.delete).not.toHaveBeenCalled();
  });

  it("edits credentials: shows configured indicators and PATCHes new values, then returns to the detail", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Plaid"));
    fireEvent.click(await screen.findByRole("button", { name: /Edit credentials/i }));

    expect(await screen.findByText("Plaid credentials")).toBeInTheDocument();
    // Client ID and Secret are both stored in the database.
    expect(screen.getAllByText("Configured")).toHaveLength(2);

    const [clientIdInput, secretInput] = screen.getAllByPlaceholderText("Leave blank to keep current");
    fireEvent.change(clientIdInput, { target: { value: "new-client-id" } });
    fireEvent.change(secretInput, { target: { value: "new-secret" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/plaid/configuration", {
        plaid_configuration: {
          client_id: "new-client-id",
          secret: "new-secret",
          environment: "production",
        },
      });
    });
    // onDone navigates back to the Plaid detail panel.
    expect(await screen.findByText("Connected institutions")).toBeInTheDocument();
  });
});

// ── Coinbase detail panel ─────────────────────────────────────────────────────

describe("Settings → Integrations → Coinbase detail", () => {
  beforeEach(() => {
    installGetStub({
      "/coinbase/configuration": COINBASE_CONFIGURED,
      "/coinbase/accounts": COINBASE_ACCOUNTS,
    });
  });

  it("lists funded accounts sorted by USD value, hiding zero balances", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Coinbase"));

    expect(await screen.findByText("BTC Wallet")).toBeInTheDocument();
    expect(screen.getByText("API key: Configured")).toBeInTheDocument();
    expect(screen.getByText("funded accounts")).toBeInTheDocument();
    expect(screen.getByText("2", { selector: ".text-4xl" })).toBeInTheDocument();

    // Sorted descending by USD value: BTC ($30k) before ETH ($5k).
    const rows = screen.getAllByRole("row");
    expect(rows[1]).toHaveTextContent("BTC Wallet");
    expect(rows[2]).toHaveTextContent("ETH Wallet");
    expect(within(rows[1]).getByText("0.500")).toBeInTheDocument();
    expect(within(rows[1]).getByText("$30,000.00")).toBeInTheDocument();

    // Zero/blank-balance accounts are hidden but counted.
    expect(screen.queryByText("SOL Wallet")).toBeNull();
    expect(screen.queryByText("USDC Wallet")).toBeNull();
    expect(screen.getByText(/2 accounts with zero balance hidden/)).toBeInTheDocument();
  });

  it("shows the no-funded-accounts empty state", async () => {
    installGetStub({
      "/coinbase/configuration": COINBASE_CONFIGURED,
      "/coinbase/accounts": [COINBASE_ACCOUNTS[2]], // zero balance only
    });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Coinbase"));

    expect(await screen.findByText("No accounts with a balance found.")).toBeInTheDocument();
  });

  it("tests the connection and renders a success result", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/coinbase/configuration/test") {
        return { ok: true, message: "Connected — 4 accounts visible" } as never;
      }
      return {} as never;
    });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Coinbase"));
    fireEvent.click(await screen.findByRole("button", { name: "Test connection" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/coinbase/configuration/test");
    });
    expect(await screen.findByText("Connected — 4 accounts visible")).toBeInTheDocument();
  });

  it("tests the connection and renders an error result when the request fails", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/coinbase/configuration/test") throw new Error("Invalid API key");
      return {} as never;
    });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Coinbase"));
    fireEvent.click(await screen.findByRole("button", { name: "Test connection" }));

    expect(await screen.findByText("Invalid API key")).toBeInTheDocument();
  });

  it("queues a transaction sync via POST /coinbase/sync", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Coinbase"));
    fireEvent.click(await screen.findByRole("button", { name: /Sync transactions/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/coinbase/sync");
    });
    expect(await screen.findByText(/Sync queued — updating shortly/)).toBeInTheDocument();
  });

  it("opens the credentials pane from the detail and saves only the fields provided", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("Coinbase"));
    fireEvent.click(await screen.findByRole("button", { name: /Edit credentials/i }));

    expect(await screen.findByText("Coinbase credentials")).toBeInTheDocument();
    expect(screen.getAllByText("Configured")).toHaveLength(2);

    // Only rotate the secret; the key id stays untouched.
    const [, secretInput] = screen.getAllByPlaceholderText("Leave blank to keep current");
    fireEvent.change(secretInput, { target: { value: "rotated-secret" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/coinbase/configuration", {
        coinbase_configuration: { api_key_secret: "rotated-secret" },
      });
    });
    // Back on the detail panel.
    expect(await screen.findByText("API key: Configured")).toBeInTheDocument();
  });
});

// ── CoinMarketCap detail panel ────────────────────────────────────────────────

describe("Settings → Integrations → CoinMarketCap detail", () => {
  beforeEach(() => {
    installGetStub({
      "/plaid/configuration": PLAID_CONFIGURED,
      "/coinbase/configuration": COINBASE_CONFIGURED,
      "/coin_market_cap/configuration": CMC_CONFIGURED,
    });
  });

  it("lists all configured providers and opens the CoinMarketCap detail", async () => {
    renderIntegrations();

    // All three configured providers show as connection rows.
    expect(await screen.findByText("Plaid")).toBeInTheDocument();
    expect(screen.getByText("Coinbase")).toBeInTheDocument();
    expect(screen.getByText("CoinMarketCap")).toBeInTheDocument();

    fireEvent.click(screen.getByText("CoinMarketCap"));

    expect(await screen.findByText(/Fetches live crypto prices/)).toBeInTheDocument();
    expect(screen.getByText("Connected")).toBeInTheDocument();
  });

  it("tests the connection and renders the API's error message", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/coin_market_cap/configuration/test") {
        return { ok: false, error: "API key rejected by CoinMarketCap" } as never;
      }
      return {} as never;
    });
    renderIntegrations();

    fireEvent.click(await screen.findByText("CoinMarketCap"));
    fireEvent.click(await screen.findByRole("button", { name: "Test connection" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/coin_market_cap/configuration/test");
    });
    expect(await screen.findByText("API key rejected by CoinMarketCap")).toBeInTheDocument();
  });

  it("edits the API key from the detail and PATCHes it", async () => {
    renderIntegrations();

    fireEvent.click(await screen.findByText("CoinMarketCap"));
    fireEvent.click(await screen.findByRole("button", { name: /Edit credentials/i }));

    expect(await screen.findByText("CoinMarketCap credentials")).toBeInTheDocument();
    expect(screen.getByText("Configured")).toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText("Leave blank to keep current"), {
      target: { value: "cmc-key-2" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/coin_market_cap/configuration", {
        coin_market_cap_configuration: { api_key: "cmc-key-2" },
      });
    });
    // onDone returns to the CMC detail panel.
    expect(await screen.findByText(/Fetches live crypto prices/)).toBeInTheDocument();
  });
});

// ── Alchemy detail panel ──────────────────────────────────────────────────────

const ALCHEMY_CONFIGURED = {
  api_key_set: true, configured: true,
  transactions_enabled: false, sync_frequency: "daily",
  auth_token_set: false, webhook_base_url: null,
  suggested_webhook_base_url: "https://fin.example.com",
  transactions_last_synced_at: null, webhooks: [],
};

const ALCHEMY_WALLETS = [
  {
    id: "aw1", address: "0xaaa0000000000000000000000000000000000001", name: "Vault",
    display_name: "Vault", networks: ["eth-mainnet"], active: true,
    last_synced_at: "2026-07-14T12:00:00Z", last_error: null,
    account: { id: "acc1", name: "Vault", balance: 12000 },
    syncs: [
      { network: "eth-mainnet", last_synced_at: "2026-07-14T12:00:00Z",
        backfill_status: "running", backfill_transfer_count: 3214, last_error: null },
    ],
  },
];

describe("Settings → Integrations → Alchemy detail", () => {
  beforeEach(() => {
    installGetStub({
      "/alchemy/configuration": ALCHEMY_CONFIGURED,
      "/alchemy/wallets": ALCHEMY_WALLETS,
    });
  });

  it("enables transaction tracking via PATCH /alchemy/configuration", async () => {
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    const toggle = await screen.findByRole("checkbox", { name: /Track on-chain transactions/i });
    fireEvent.click(toggle);

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/alchemy/configuration", {
        alchemy_configuration: { transactions_enabled: true },
      });
    });
  });

  it("shows frequency select, backfill progress, and backfill action when transactions are on", async () => {
    installGetStub({
      "/alchemy/configuration": { ...ALCHEMY_CONFIGURED, transactions_enabled: true },
      "/alchemy/wallets": ALCHEMY_WALLETS,
    });
    apiMock.post.mockResolvedValue({ status: "queued" } as never);
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    // Frequency select PATCHes the new cadence.
    const select = await screen.findByLabelText(/Check for new activity/i);
    fireEvent.change(select, { target: { value: "realtime" } });
    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/alchemy/configuration", {
        alchemy_configuration: { sync_frequency: "realtime" },
      });
    });

    // Backfill progress line from wallet sync state.
    expect(screen.getByText(/Backfilling… 3,214 transfers/)).toBeInTheDocument();

    // Backfill action posts after confirm.
    fireEvent.click(screen.getByRole("button", { name: /Backfill history for Vault/i }));
    fireEvent.click(await screen.findByRole("button", { name: "Backfill" }));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/alchemy/wallets/aw1/backfill");
    });
  });

  it("warns when real-time is selected without webhook credentials", async () => {
    installGetStub({
      "/alchemy/configuration": { ...ALCHEMY_CONFIGURED, transactions_enabled: true, sync_frequency: "realtime" },
      "/alchemy/wallets": ALCHEMY_WALLETS,
    });
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    expect(await screen.findByText(/Real-time sync needs a Notify auth token/)).toBeInTheDocument();
  });
});


describe("Settings → Integrations → Alchemy actions", () => {
  beforeEach(() => {
    installGetStub({
      "/alchemy/configuration": ALCHEMY_CONFIGURED,
      "/alchemy/wallets": ALCHEMY_WALLETS,
    });
  });

  it("tests the connection and renders the success result", async () => {
    apiMock.post.mockResolvedValueOnce({ ok: true, message: "Alchemy key accepted" } as never);
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/alchemy/configuration/test");
    });
    expect(await screen.findByText("Alchemy key accepted")).toBeInTheDocument();
  });

  it("renders the error result when the connection test fails", async () => {
    apiMock.post.mockRejectedValueOnce(new Error("Alchemy rejected the API key"));
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    expect(await screen.findByText("Alchemy rejected the API key")).toBeInTheDocument();
  });

  it("queues a balance sync via POST /alchemy/sync and confirms it was queued", async () => {
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    fireEvent.click(await screen.findByRole("button", { name: /Sync balances/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/alchemy/sync");
    });
    expect(await screen.findByText(/Sync queued/)).toBeInTheDocument();
  });

  it("reports a failed sync instead of claiming it was queued", async () => {
    apiMock.post.mockRejectedValueOnce(new Error("Alchemy is unreachable"));
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    fireEvent.click(await screen.findByRole("button", { name: /Sync balances/i }));

    expect(await screen.findByText(/Sync failed: Alchemy is unreachable/)).toBeInTheDocument();
  });

  it("removes a tracked wallet via DELETE /alchemy/wallets/:id", async () => {
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    fireEvent.click(await screen.findByLabelText("Remove Vault"));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Remove wallet?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/alchemy/wallets/aw1");
    });
  });

  it("keeps the wallet when the remove confirm is declined", async () => {
    renderIntegrations();
    fireEvent.click(await screen.findByText("Alchemy"));

    fireEvent.click(await screen.findByLabelText("Remove Vault"));
    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
    expect(apiMock.delete).not.toHaveBeenCalled();
  });
});


// ── RentCast ─────────────────────────────────────────────────────────────────
//
// This provider is the reason the audit happened: every RentCast endpoint had a
// request spec, but nothing exercised the browser side, so a broken settings
// screen could ship green. These cover the four calls the UI makes.

const RENTCAST_UNCONFIGURED = {
  api_key_set: false, configured: false, last_synced_at: null, property_count: 0,
  quota: { used: 0, limit: 50, remaining: 50, period_start: "2026-08-01", resets_on: "2026-09-01" },
};
const RENTCAST_CONFIGURED = {
  api_key_set: true, configured: true, last_synced_at: "2026-08-03T13:15:00Z", property_count: 2,
  quota: { used: 12, limit: 50, remaining: 38, period_start: "2026-08-01", resets_on: "2026-09-01" },
};

describe("Settings → Integrations → RentCast", () => {
  it("connects RentCast from the provider picker, PATCHing only the key that was typed", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_UNCONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("RentCast"));

    expect(await screen.findByText("Connect RentCast")).toBeInTheDocument();
    const key = await screen.findByLabelText("API Key");
    expect(key).toHaveAttribute("placeholder", "Enter your RentCast API key");

    fireEvent.change(key, { target: { value: "rc-live-key" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/rentcast/configuration", {
        rentcast_configuration: { api_key: "rc-live-key" },
      });
    });
  });

  it("sends a raised monthly limit alongside the key for a paid plan", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_UNCONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("RentCast"));

    fireEvent.change(await screen.findByLabelText("API Key"), { target: { value: "rc-key" } });
    fireEvent.change(screen.getByLabelText(/Monthly request limit/i), { target: { value: "1000" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/rentcast/configuration", {
        rentcast_configuration: { api_key: "rc-key", monthly_request_limit: "1000" },
      });
    });
  });

  it("keeps Save disabled until something is entered on a fresh connection", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_UNCONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("RentCast"));

    const save = await screen.findByRole("button", { name: "Save" });
    expect(save).toBeDisabled();

    fireEvent.change(await screen.findByLabelText("API Key"), { target: { value: "k" } });
    expect(save).toBeEnabled();
  });

  it("surfaces a save failure instead of silently closing the form", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_UNCONFIGURED });
    apiMock.patch.mockRejectedValueOnce(new Error("Internal server error"));
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("RentCast"));

    fireEvent.change(await screen.findByLabelText("API Key"), { target: { value: "bad" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(await screen.findByText(/Failed to save/i)).toBeInTheDocument();
  });

  it("shows quota usage, property count and last sync on the connected detail", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_CONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("RentCast"));

    expect(await screen.findByText("12 / 50")).toBeInTheDocument();
    expect(screen.getByText(/2 properties/)).toBeInTheDocument();
    expect(screen.getByText(/requests used/)).toBeInTheDocument();
    expect(screen.getByText(/Last sync/)).toBeInTheDocument();
  });

  it("tests the connection and renders the success message", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_CONFIGURED });
    apiMock.post.mockResolvedValueOnce({
      ok: true, message: "Connected — RentCast accepted the API key",
    } as never);
    renderIntegrations();

    fireEvent.click(await screen.findByText("RentCast"));
    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/rentcast/configuration/test");
    });
    expect(await screen.findByText(/RentCast accepted the API key/)).toBeInTheDocument();
  });

  it("renders the API's error message when the key is rejected", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_CONFIGURED });
    apiMock.post.mockRejectedValueOnce(new Error("RentCast rejected the request (401)"));
    renderIntegrations();

    fireEvent.click(await screen.findByText("RentCast"));
    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    expect(await screen.findByText(/RentCast rejected the request \(401\)/)).toBeInTheDocument();
  });

  it("removes the connection after confirming", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_CONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("RentCast"));
    fireEvent.click(await screen.findByRole("button", { name: /Remove/i }));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Remove RentCast?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/rentcast/configuration");
    });
  });

  it("does not remove the connection when the confirm is declined", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_CONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("RentCast"));
    fireEvent.click(await screen.findByRole("button", { name: /Remove/i }));

    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
    expect(apiMock.delete).not.toHaveBeenCalled();
  });

  it("edits an existing key from the detail, showing Configured and allowing a blank keep", async () => {
    installGetStub({ "/rentcast/configuration": RENTCAST_CONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("RentCast"));
    fireEvent.click(await screen.findByRole("button", { name: /Edit credentials/i }));

    expect(await screen.findByText("RentCast credentials")).toBeInTheDocument();
    expect(screen.getByText("Configured")).toBeInTheDocument();
    expect(screen.getByLabelText("API Key")).toHaveAttribute("placeholder", "Leave blank to keep current");

    // Saving with only a new limit must not clear the stored key.
    fireEvent.change(screen.getByLabelText(/Monthly request limit/i), { target: { value: "250" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/rentcast/configuration", {
        rentcast_configuration: { monthly_request_limit: "250" },
      });
    });
  });
});

// ── Tiingo ───────────────────────────────────────────────────────────────────

const TIINGO_UNCONFIGURED = { api_key_set: false, configured: false };
const TIINGO_CONFIGURED = { api_key_set: true, configured: true };

describe("Settings → Integrations → Tiingo", () => {
  it("connects Tiingo from the provider picker via PATCH /tiingo/configuration", async () => {
    installGetStub({ "/tiingo/configuration": TIINGO_UNCONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("Tiingo"));

    fireEvent.change(await screen.findByLabelText("API Key"), { target: { value: "tiingo-key" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/tiingo/configuration", {
        tiingo_configuration: { api_key: "tiingo-key" },
      });
    });
  });

  it("tests the connection and renders the result", async () => {
    installGetStub({ "/tiingo/configuration": TIINGO_CONFIGURED });
    apiMock.post.mockResolvedValueOnce({ ok: true, message: "Tiingo accepted the key" } as never);
    renderIntegrations();

    fireEvent.click(await screen.findByText("Tiingo"));
    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/tiingo/configuration/test");
    });
    expect(await screen.findByText("Tiingo accepted the key")).toBeInTheDocument();
  });

  it("renders a failed connection test", async () => {
    installGetStub({ "/tiingo/configuration": TIINGO_CONFIGURED });
    apiMock.post.mockRejectedValueOnce(new Error("Tiingo rejected the token"));
    renderIntegrations();

    fireEvent.click(await screen.findByText("Tiingo"));
    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    expect(await screen.findByText("Tiingo rejected the token")).toBeInTheDocument();
  });

  it("removes the connection after confirming", async () => {
    installGetStub({ "/tiingo/configuration": TIINGO_CONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Tiingo"));
    fireEvent.click(await screen.findByRole("button", { name: /Remove/i }));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Remove Tiingo?")).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/tiingo/configuration");
    });
  });

  it("edits an existing key from the detail", async () => {
    installGetStub({ "/tiingo/configuration": TIINGO_CONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Tiingo"));
    fireEvent.click(await screen.findByRole("button", { name: /Edit credentials/i }));

    expect(await screen.findByText("Configured")).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("API Key"), { target: { value: "rotated" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/tiingo/configuration", {
        tiingo_configuration: { api_key: "rotated" },
      });
    });
  });
});

// ── Alpha Vantage ────────────────────────────────────────────────────────────

const AV_UNCONFIGURED = { api_key_set: false, configured: false };
const AV_CONFIGURED = { api_key_set: true, configured: true };

describe("Settings → Integrations → Alpha Vantage", () => {
  it("connects Alpha Vantage via PATCH /alpha_vantage/configuration", async () => {
    installGetStub({ "/alpha_vantage/configuration": AV_UNCONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("Alpha Vantage"));

    fireEvent.change(await screen.findByLabelText("API Key"), { target: { value: "av-key" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/alpha_vantage/configuration", {
        alpha_vantage_configuration: { api_key: "av-key" },
      });
    });
  });

  it("tests the connection and renders the result", async () => {
    installGetStub({ "/alpha_vantage/configuration": AV_CONFIGURED });
    apiMock.post.mockResolvedValueOnce({ ok: true, message: "Alpha Vantage responded" } as never);
    renderIntegrations();

    fireEvent.click(await screen.findByText("Alpha Vantage"));
    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/alpha_vantage/configuration/test");
    });
    expect(await screen.findByText("Alpha Vantage responded")).toBeInTheDocument();
  });

  it("renders the API's error when the rate limit is hit", async () => {
    installGetStub({ "/alpha_vantage/configuration": AV_CONFIGURED });
    apiMock.post.mockRejectedValueOnce(new Error("Rate limit reached — try again tomorrow"));
    renderIntegrations();

    fireEvent.click(await screen.findByText("Alpha Vantage"));
    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    expect(await screen.findByText(/Rate limit reached/)).toBeInTheDocument();
  });

  it("edits an existing key from the detail", async () => {
    installGetStub({ "/alpha_vantage/configuration": AV_CONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Alpha Vantage"));
    fireEvent.click(await screen.findByRole("button", { name: /Edit credentials/i }));

    expect(await screen.findByText("Configured")).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("API Key"), { target: { value: "rotated-av" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/alpha_vantage/configuration", {
        alpha_vantage_configuration: { api_key: "rotated-av" },
      });
    });
  });
});

// ── Office ───────────────────────────────────────────────────────────────────
//
// The one provider that is a destination rather than a source: two fields (the
// instance URL and a token minted there) and a detail pane listing the
// spreadsheets Fin has made.

const OFFICE_UNCONFIGURED = {
  configured: false, api_key_set: false, base_url: null, default_folder_id: null,
  source: null, datasets: [{ key: "transactions", label: "Transactions" }], sheet_count: 0,
};
const OFFICE_CONFIGURED = {
  configured: true, api_key_set: true, base_url: "https://office.example", default_folder_id: null,
  source: "configuration", datasets: [{ key: "transactions", label: "Transactions" }], sheet_count: 1,
};
const OFFICE_SHEETS = [
  {
    id: "os1", dataset: "transactions", dataset_label: "Transactions", title: "Groceries 2026",
    document_id: 77, sheet_name: "Sheet1", url: "https://office.example/d/77", filters: {},
    row_count: 412, last_exported_at: "2026-09-16T10:00:00Z", last_error: null,
    created_at: "2026-09-01T10:00:00Z",
  },
];

describe("Settings → Integrations → Office", () => {
  it("connects Office with the instance URL and a token from the provider picker", async () => {
    installGetStub({ "/office/configuration": OFFICE_UNCONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("Office"));

    expect(await screen.findByText("Connect Office")).toBeInTheDocument();
    fireEvent.change(await screen.findByLabelText("Office URL"), {
      target: { value: "https://office.example" },
    });
    fireEvent.change(screen.getByLabelText("API token"), { target: { value: "office_tok" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/office/configuration", {
        office_configuration: { api_key: "office_tok", base_url: "https://office.example" },
      });
    });
  });

  it("won't save without an instance URL to point at", async () => {
    installGetStub({ "/office/configuration": OFFICE_UNCONFIGURED });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Add your first connection"));
    fireEvent.click(await screen.findByText("Office"));

    fireEvent.change(await screen.findByLabelText("API token"), { target: { value: "office_tok" } });
    expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
  });

  it("keeps the saved URL when only the token is being replaced", async () => {
    installGetStub({ "/office/configuration": OFFICE_CONFIGURED, "/office/sheet_exports": OFFICE_SHEETS });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Office"));
    fireEvent.click(await screen.findByRole("button", { name: /Edit credentials/i }));

    const url = await screen.findByLabelText("Office URL");
    expect(url).toHaveAttribute("placeholder", "https://office.example");
    fireEvent.change(screen.getByLabelText("API token"), { target: { value: "office_new" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/office/configuration", {
        office_configuration: { api_key: "office_new" },
      });
    });
  });

  it("lists the linked spreadsheets on the connected detail", async () => {
    installGetStub({ "/office/configuration": OFFICE_CONFIGURED, "/office/sheet_exports": OFFICE_SHEETS });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Office"));

    expect(await screen.findByText("Groceries 2026")).toBeInTheDocument();
    expect(screen.getByText(/412 rows/)).toBeInTheDocument();
    expect(screen.getByLabelText("Open Groceries 2026 in Office")).toHaveAttribute(
      "href",
      "https://office.example/d/77",
    );
  });

  it("says so when the last refresh of a sheet failed", async () => {
    installGetStub({
      "/office/configuration": OFFICE_CONFIGURED,
      "/office/sheet_exports": [{ ...OFFICE_SHEETS[0], last_error: "You can't edit this spreadsheet" }],
    });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Office"));

    expect(await screen.findByText(/Last refresh failed: You can't edit this spreadsheet/)).toBeInTheDocument();
  });

  it("tests the connection and renders Office's own error", async () => {
    installGetStub({ "/office/configuration": OFFICE_CONFIGURED, "/office/sheet_exports": [] });
    apiMock.post.mockRejectedValueOnce(new Error("Office rejected the API token"));
    renderIntegrations();

    fireEvent.click(await screen.findByText("Office"));
    fireEvent.click(await screen.findByRole("button", { name: /Test connection/i }));

    await waitFor(() => expect(apiMock.post).toHaveBeenCalledWith("/office/configuration/test"));
    expect(await screen.findByText("Office rejected the API token")).toBeInTheDocument();
  });

  it("warns that the sheets stay in Office before removing the connection", async () => {
    installGetStub({ "/office/configuration": OFFICE_CONFIGURED, "/office/sheet_exports": OFFICE_SHEETS });
    renderIntegrations();

    fireEvent.click(await screen.findByText("Office"));
    fireEvent.click(await screen.findByRole("button", { name: /Remove/i }));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Remove Office?")).toBeInTheDocument();
    expect(within(dialog).getByText(/left exactly as they are/)).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => expect(apiMock.delete).toHaveBeenCalledWith("/office/configuration"));
  });
});
