import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
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

// Always today, regardless of when the suite runs.
const TODAY = new Date(new Date().setMinutes(0, 0, 0)).toISOString();
// Always yesterday: yesterday at noon local time.
const YESTERDAY = (() => {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  d.setHours(12, 0, 0, 0);
  return d.toISOString();
})();
// A fixed older local date → "May 20, 2026" group.
const OLDER = new Date(2026, 4, 20, 10, 0, 0).toISOString();

const ENTRIES = [
  { id: "e1", occurred_at: TODAY, source: "plaid_sync", event: "sync.completed", severity: "info",
    summary: "Plaid sync completed — 12 new transactions", payload: { added: 12 },
    subject_type: "PlaidItem", subject_id: "p1", trace_id: "tr-1",
    caused_by_type: null, caused_by_id: null, duration_ms: 2340 },
  { id: "e2", occurred_at: YESTERDAY, source: "market_prices", event: "prices.refreshed", severity: "warning",
    summary: "Price refresh skipped 2 tickers", payload: { skipped: ["ABC", "XYZ"] },
    subject_type: null, subject_id: null, trace_id: null,
    caused_by_type: null, caused_by_id: null, duration_ms: 812 },
  { id: "e3", occurred_at: OLDER, source: "import", event: "import.failed", severity: "error",
    summary: "CSV import failed", payload: { error: "bad row" },
    subject_type: null, subject_id: null, trace_id: null,
    caused_by_type: null, caused_by_id: null, duration_ms: null },
];

// Lead entry of the multi-entry episode below: worst severity, then latest.
const G4_LEAD = {
  id: "e4", occurred_at: TODAY, source: "import", event: "import.failed", severity: "error",
  summary: "Nightly import failed on row 88", payload: { error: "bad row 88" },
  subject_type: null, subject_id: null, trace_id: "tr-4",
  caused_by_type: null, caused_by_id: null, duration_ms: 4200,
};

const wrap = (entry: (typeof ENTRIES)[number], severities: Record<string, number>) => ({
  trace_id: entry.trace_id, count: 1, severities, sources: [entry.source],
  first_at: entry.occurred_at, last_at: entry.occurred_at, lead: entry,
});

const GROUPS = {
  groups: [
    wrap(ENTRIES[0], { info: 1 }),
    {
      trace_id: "tr-4", count: 6, severities: { info: 4, warning: 1, error: 1 },
      sources: ["workflow", "plaid_sync", "import"],
      first_at: TODAY, last_at: TODAY, lead: G4_LEAD,
    },
    wrap(ENTRIES[1], { warning: 1 }),
    wrap(ENTRIES[2], { error: 1 }),
  ],
  meta: { page: 1, per_page: 30, total: 4 },
};

const TRACE = {
  trace_id: "tr-1",
  entries: [
    ENTRIES[0],
    { id: "te2", occurred_at: TODAY, source: "workflow", event: "workflow.triggered", severity: "info",
      summary: "Workflow triggered by plaid.sync_completed", payload: null,
      subject_type: null, subject_id: null, trace_id: "tr-1",
      caused_by_type: "ActivityEntry", caused_by_id: "e1", duration_ms: null },
  ],
  workflow_runs: [
    { id: "r1", workflow_id: "w1", workflow_name: "Notify on sync", event_type: "plaid.sync_completed",
      event_payload: null, subject_type: "PlaidItem", subject_id: "p1", status: "completed",
      error: null, started_at: TODAY, finished_at: TODAY, created_at: TODAY },
  ],
  notifications: [
    { id: "n1", title: "Sync finished", severity: "info", created_at: TODAY },
  ],
};

const TRACE4 = {
  trace_id: "tr-4",
  entries: [
    { id: "t4e1", occurred_at: TODAY, source: "workflow", event: "workflow.completed", severity: "info",
      summary: "Workflow applied category to 6 transactions", payload: null,
      subject_type: null, subject_id: null, trace_id: "tr-4",
      caused_by_type: null, caused_by_id: null, duration_ms: null },
    G4_LEAD,
  ],
  workflow_runs: [],
  notifications: [],
};

const HEALTH = {
  sources: [
    { source: "plaid_sync", event: "sync.completed", severity: "info",
      summary: "Synced 12 transactions", occurred_at: TODAY, duration_ms: 2340 },
    { source: "import", event: "import.failed", severity: "error",
      summary: "Import failed: bad.csv", occurred_at: YESTERDAY, duration_ms: null },
  ],
  workflows: { runs_7d: 40, failed_7d: 4, waiting: 1 },
  errors_24h: 5,
  market_data: {
    providers: [
      { provider: "alpha_vantage", instruments: 42, failing: 0, last_error: null },
      { provider: "coin_market_cap", instruments: 7, failing: 2, last_error: "429 Too Many Requests from CoinMarketCap" },
    ],
    stale_held_instruments: 6,
    open_drift_findings: 1,
  },
};

const HEALTH_ALL_CLEAR = {
  sources: HEALTH.sources.map((s) => ({ ...s, severity: "info", summary: "OK" })),
  workflows: { runs_7d: 40, failed_7d: 0, waiting: 0 },
  errors_24h: 0,
  market_data: {
    providers: [{ provider: "alpha_vantage", instruments: 42, failing: 0, last_error: null }],
    stale_held_instruments: 0,
    open_drift_findings: 0,
  },
};

const ISSUES = [
  { id: "i1", title: "Holdings drift: AAPL — Brokerage", severity: "warning",
    body: "The custodian reports 110.0 but the transaction ledger accounts for 100.0 (quantity drift). Transactions are likely missing or misclassified.",
    source: "reconciliation", key: "reconciliation:acc1:sec1", dismissed_at: null, created_at: TODAY },
  // Non-reconciliation issue — must not surface in the drift inbox.
  { id: "i2", title: "Duplicate merchant detected", severity: "warning",
    body: null, source: "system_audit", key: null, dismissed_at: null, created_at: TODAY },
  // Drift finding without a serialized key — dismissable but not acceptable.
  { id: "i3", title: "Holdings drift: TSLA — IRA", severity: "warning",
    body: null, source: "reconciliation", key: null, dismissed_at: null, created_at: TODAY },
];

beforeEach(() => {
  clearToken();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());
  window.HTMLElement.prototype.scrollIntoView = vi.fn();

  apiMock.post.mockResolvedValue({} as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                 household: { id: "h1", name: "H", role: "admin" } } as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
    if (path === "/system_health") return HEALTH as never;
    if (path === "/issues") return ISSUES as never;
    if (path === "/activity/trace/tr-1") return TRACE as never;
    if (path === "/activity/trace/tr-4") return TRACE4 as never;
    if (path.startsWith("/activity?")) return GROUPS as never;
    return [] as never;
  });
});

describe("Activity: timeline", () => {
  it("renders day-grouped rows with severity, source badge, summary, and duration", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    expect(await screen.findByRole("heading", { level: 1, name: "Activity" })).toBeInTheDocument();

    // Day group headers
    expect(await screen.findByText("Today")).toBeInTheDocument();
    expect(screen.getByText("Yesterday")).toBeInTheDocument();
    expect(screen.getByText("May 20, 2026")).toBeInTheDocument();

    // Row content
    expect(screen.getByText("Plaid sync completed — 12 new transactions")).toBeInTheDocument();
    expect(screen.getByText("Price refresh skipped 2 tickers")).toBeInTheDocument();
    expect(screen.getByText("CSV import failed")).toBeInTheDocument();

    // Source badges (plaid also appears in the health strip card)
    expect(screen.getAllByText("Plaid").length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("Market prices")).toBeInTheDocument();

    // Severity dots carry the severity as a title
    expect(screen.getAllByTitle("warning").length).toBeGreaterThanOrEqual(1);
    expect(screen.getAllByTitle("error").length).toBeGreaterThanOrEqual(1);

    // Durations formatted
    expect(screen.getAllByText("2.3s").length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("812ms")).toBeInTheDocument();

    // Initial fetch is the unfiltered, grouped first page
    expect(apiMock.get).toHaveBeenCalledWith("/activity?grouped=true&page=1");
  });

  it("shows the empty state when there are no entries", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      if (path === "/system_health") return HEALTH as never;
      if (path.startsWith("/activity?")) return { groups: [], meta: { page: 1, per_page: 30, total: 0 } } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/activity", initialToken: "tok" });

    expect(await screen.findByText("No activity yet.")).toBeInTheDocument();
  });
});

describe("Activity: health strip", () => {
  it("renders plain-language tiles with subtitles plus per-source cards", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    // No queue tiles anymore; "Errors" appears as both a tile and a chip
    expect(await screen.findByText("Workflow failures")).toBeInTheDocument();
    expect(screen.queryByText(/Queue/)).not.toBeInTheDocument();
    expect(screen.getAllByText("Errors").length).toBe(2);

    expect(screen.getByText("last 24 hours")).toBeInTheDocument();
    expect(screen.getByText("5")).toBeInTheDocument();
    expect(screen.getByText("last 7 days")).toBeInTheDocument();
    expect(screen.getByText("4")).toBeInTheDocument();
    expect(screen.getByText("Holdings drift")).toBeInTheDocument();
    expect(screen.getByText("ledger vs. custodian mismatches")).toBeInTheDocument();
    expect(screen.getByText("Stale prices")).toBeInTheDocument();
    expect(screen.getByText("held instruments without a fresh price")).toBeInTheDocument();
    expect(screen.getByText("6")).toBeInTheDocument();

    // Source cards show the last summary
    expect(screen.getByText(/Synced 12 transactions/)).toBeInTheDocument();
    expect(screen.getByText(/Import failed: bad\.csv/)).toBeInTheDocument();
  });

  it("collapses to a single healthy line when nothing is wrong", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      if (path === "/system_health") return HEALTH_ALL_CLEAR as never;
      if (path === "/issues") return [] as never;
      if (path.startsWith("/activity?")) return GROUPS as never;
      return [] as never;
    });

    renderApp({ initialPath: "/activity", initialToken: "tok" });

    expect(await screen.findByText(/All systems healthy — syncs, workflows, prices, and reconciliation are clean/)).toBeInTheDocument();
    expect(screen.getByText(/Last sync/)).toBeInTheDocument();

    // No tiles or provider cards occupy space
    expect(screen.queryByText("Workflow failures")).not.toBeInTheDocument();
    expect(screen.queryByText("Stale prices")).not.toBeInTheDocument();
    expect(screen.queryByText("Alpha Vantage")).not.toBeInTheDocument();
  });

  it("the errors tile applies the timeline's error filter", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /Errors.*last 24 hours/ }));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/activity?severity=error&grouped=true&page=1");
    });
    // The matching filter tab reflects the active filter
    expect(screen.getByRole("tab", { name: "Errors" })).toHaveAttribute("aria-selected", "true");
  });

  it("the workflow-failures tile filters to workflow source + error severity", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /Workflow failures.*last 7 days/ }));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/activity?source=workflow&severity=error&grouped=true&page=1");
    });
  });

  it("the holdings-drift tile scrolls to the reconciliation panel", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /Holdings drift/ }));

    expect(window.HTMLElement.prototype.scrollIntoView).toHaveBeenCalled();
  });

  it("a source card applies the timeline's matching source filter and carries a tooltip", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    const plaidCard = (await screen.findByText(/Synced 12 transactions/)).closest("button");
    expect(plaidCard).not.toBeNull();
    expect(plaidCard!.title).toContain("Synced 12 transactions");
    expect(plaidCard!.title).toMatch(/ago/);

    await userEvent.click(plaidCard!);
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(
        "/activity?source=plaid_sync%2Ccoinbase_sync%2Cmarket_prices%2Ccrypto_prices&grouped=true&page=1"
      );
    });
  });

  it("provider cards explain failing counts with the last error in a tooltip", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    // Healthy provider: quiet state, no number
    const av = (await screen.findByText("Alpha Vantage")).closest("a");
    expect(av).toHaveTextContent("healthy");
    expect(av?.textContent).not.toContain("failing");
    expect(av?.className).not.toContain("border-negative/50");
    expect(av).toHaveAttribute("href", "/market");

    // Failing provider: "N of M" phrasing, red border, last_error + retry note tooltip
    const cmc = screen.getByText("CoinMarketCap").closest("a");
    expect(cmc).toHaveTextContent("2 of 7 instruments failing");
    expect(cmc?.className).toContain("border-negative/50");
    expect(cmc?.getAttribute("title")).toContain("429 Too Many Requests from CoinMarketCap");
    expect(cmc?.getAttribute("title")).toContain("Failed fetches retry automatically with backoff.");
    expect(cmc).toHaveAttribute("href", "/market");
  });
});

describe("Activity: reconciliation inbox", () => {
  it("lists open drift findings with title and body, excluding other issues", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    expect(await screen.findByText("Reconciliation")).toBeInTheDocument();
    expect(await screen.findByText("Holdings drift: AAPL — Brokerage")).toBeInTheDocument();
    expect(screen.getByText(/custodian reports 110\.0/)).toBeInTheDocument();

    // Intro sentence explains what the findings mean
    expect(screen.getByText(/These holdings differ between your transaction history and what the custodian reports/)).toBeInTheDocument();

    // Non-reconciliation issues stay out of the inbox
    expect(screen.queryByText("Duplicate merchant detected")).not.toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/issues");
  });

  it("dismisses a finding via DELETE /issues/:id", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await screen.findByText("Holdings drift: AAPL — Brokerage");
    await userEvent.click(screen.getAllByTitle("Dismiss")[0]);

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/issues/i1");
    });
  });

  it("accepts a finding: POSTs its key and shows the adjustment inline", async () => {
    apiMock.post.mockResolvedValue({ status: "adjusted", delta: 60 } as never);
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await screen.findByText("Holdings drift: AAPL — Brokerage");

    // Only the finding with a serialized reconciliation key gets the button
    expect(screen.getByText("Holdings drift: TSLA — IRA")).toBeInTheDocument();
    const acceptButtons = screen.getAllByRole("button", { name: "Accept balance" });
    expect(acceptButtons).toHaveLength(1);

    await userEvent.click(acceptButtons[0]);
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/reconciliation/accept", { key: "reconciliation:acc1:sec1" });
    });
    expect(await screen.findByText("Adjusted by +60")).toBeInTheDocument();
  });

  it("reports an already-synced holding without an adjustment", async () => {
    apiMock.post.mockResolvedValue({ status: "in_sync", delta: 0 } as never);
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await userEvent.click((await screen.findAllByRole("button", { name: "Accept balance" }))[0]);

    expect(await screen.findByText("Already in sync")).toBeInTheDocument();
  });

  it("'Accept all' confirms with the adjustment explanation, POSTs, and shows a queued notice", async () => {
    apiMock.post.mockResolvedValue({ status: "queued" } as never);

    renderApp({ initialPath: "/activity", initialToken: "tok" });
    await userEvent.click(await screen.findByRole("button", { name: "Accept all (2)" }));

    // The confirm dialog explains what accepting writes
    expect(await screen.findByText("Accept all 2 custodian balances?")).toBeInTheDocument();
    expect(screen.getByText(/balance-adjustment transaction/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Accept all" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/reconciliation/accept_all", {});
    });
    expect(await screen.findByText(/Queued — balance adjustments/)).toBeInTheDocument();
  });

  it("does not POST accept_all when the confirm is dismissed", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });
    await userEvent.click(await screen.findByRole("button", { name: "Accept all (2)" }));

    await screen.findByText("Accept all 2 custodian balances?");
    await userEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(apiMock.post).not.toHaveBeenCalledWith("/reconciliation/accept_all", {});
  });

  it("shows the explanatory empty state when there are no drift findings", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      if (path === "/system_health") return HEALTH as never;
      if (path === "/issues") return [ISSUES[1]] as never;
      if (path.startsWith("/activity?")) return GROUPS as never;
      return [] as never;
    });

    renderApp({ initialPath: "/activity", initialToken: "tok" });

    expect(await screen.findByText(/Your transaction history matches the holdings your brokerages report — no missing or extra positions detected/)).toBeInTheDocument();
    expect(screen.queryByText("Ledger and custodians agree")).not.toBeInTheDocument();
  });
});

describe("Activity: filter chips", () => {
  it("changes the query for source-group and error filters", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("tab", { name: "Syncs" }));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(
        "/activity?source=plaid_sync%2Ccoinbase_sync%2Cmarket_prices%2Ccrypto_prices&grouped=true&page=1"
      );
    });

    await userEvent.click(screen.getByRole("tab", { name: "Errors" }));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/activity?severity=error&grouped=true&page=1");
    });

    await userEvent.click(screen.getByRole("tab", { name: "System" }));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith(
        "/activity?source=transfer_detection%2Crecurring_detection%2Cmerchant_rules%2Csystem_audit&grouped=true&page=1"
      );
    });
  });
});

describe("Activity: grouped rows", () => {
  it("renders a multi-entry group with count pill, lead summary, sources label, and worst severity", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    const groupButton = await screen.findByRole("button", { name: /Nightly import failed on row 88/ });

    expect(within(groupButton).getByText("6 events")).toBeInTheDocument();
    expect(within(groupButton).getByText("3 sources")).toBeInTheDocument();
    // Worst severity wins the dot: error > warning > info
    expect(within(groupButton).getByTitle("error")).toBeInTheDocument();
    // Relative last_at carries the first → last range as a title
    expect(within(groupButton).getByTitle(/→/)).toBeInTheDocument();

    // Single-entry groups still render as plain rows
    expect(screen.getByText("Plaid sync completed — 12 new transactions")).toBeInTheDocument();
    expect(screen.getAllByText("2.3s").length).toBeGreaterThanOrEqual(1);
  });

  it("expanding a group opens the trace episode via the existing TracePanel", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /Nightly import failed on row 88/ }));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/activity/trace/tr-4");
    });
    expect(await screen.findByText("Workflow applied category to 6 transactions")).toBeInTheDocument();
  });
});

describe("Activity: trace panel", () => {
  it("expands a traced row into the episode: entries, workflow runs, notifications", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /Plaid sync completed/ }));

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/activity/trace/tr-1");
    });

    // Mini-timeline includes the downstream entry
    expect(await screen.findByText("Workflow triggered by plaid.sync_completed")).toBeInTheDocument();

    // Workflow run with status badge, linking to the workflow's runs page
    expect(screen.getByText("Workflow runs")).toBeInTheDocument();
    const runLink = screen.getByRole("link", { name: "Notify on sync" });
    expect(runLink).toHaveAttribute("href", "/workflows/w1/runs");
    expect(screen.getByText("completed")).toBeInTheDocument();

    // Notifications
    expect(screen.getByText("Notifications")).toBeInTheDocument();
    expect(screen.getByText("Sync finished")).toBeInTheDocument();
  });

  it("expands an untraced row to its payload JSON without fetching a trace", async () => {
    renderApp({ initialPath: "/activity", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /Price refresh skipped/ }));

    expect(await screen.findByText(/"skipped"/)).toBeInTheDocument();
    expect(apiMock.get).not.toHaveBeenCalledWith(expect.stringContaining("/activity/trace"));
  });
});

describe("Activity: pagination", () => {
  it("pages through results", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      if (path === "/system_health") return HEALTH as never;
      if (path.startsWith("/activity?")) return { groups: GROUPS.groups, meta: { page: 1, per_page: 30, total: 120 } } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/activity", initialToken: "tok" });

    expect(await screen.findByText("Page 1 of 4 · 120 groups")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Next" }));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/activity?grouped=true&page=2");
    });
  });
});
