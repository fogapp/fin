import { describe, it, expect, beforeEach, vi } from "vitest";
import { fireEvent, screen, waitFor } from "@testing-library/react";
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

const TX_FIELDS = {
  description: { operators: ["contains", "equals"] },
  amount: { operators: ["greater_than", "less_than"] },
};

const CATALOG = {
  triggers: [
    { type: "cash_transaction.created", subject_type: "CashTransaction", fields: TX_FIELDS },
    { type: "cash_transaction.updated", subject_type: "CashTransaction", fields: TX_FIELDS },
    { type: "plaid.sync_completed", subject_type: "PlaidItem", fields: { status: { operators: ["equals"] } } },
    { type: "monitor", subject_type: null, fields: {} },
  ],
  actions: ["assign_category", "set_memo", "notify"],
};

const WORKFLOWS = [
  {
    id: "w1", name: "Categorize coffee", description: "Tag coffee purchases",
    trigger_type: "cash_transaction.created", trigger_config: {}, active: true, position: 0,
    seed_key: null, next_scheduled_at: null, schedule_summary: null,
    created_at: "2026-06-01T00:00:00Z", updated_at: "2026-06-01T00:00:00Z",
    run_count: 3, last_run_status: "completed", last_run_at: "2026-07-01T12:00:00Z",
  },
  {
    id: "w2", name: "Balance monitor", description: null,
    trigger_type: "monitor", trigger_config: { subject: "account", match_all: true, conditions: [] },
    active: false, position: 1,
    seed_key: null, next_scheduled_at: null, schedule_summary: null,
    created_at: "2026-06-01T00:00:00Z", updated_at: "2026-06-01T00:00:00Z",
    run_count: 0, last_run_status: null, last_run_at: null,
  },
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
    if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                 household: { id: "h1", name: "H", role: "admin" } } as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/workflows") return WORKFLOWS as never;
    if (path === "/workflows/catalog") return CATALOG as never;
    if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
    return [] as never;
  });
});

describe("Workflows: index", () => {
  it("groups workflows by trigger family with trigger summary and run stats", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    expect(await screen.findByRole("heading", { level: 2, name: "Workflows" })).toBeInTheDocument();
    expect(await screen.findByText("Categorize coffee")).toBeInTheDocument();
    expect(screen.getByText("Balance monitor")).toBeInTheDocument();

    // Family names render as both a filter tab and a section header on All
    expect(screen.getAllByText("Transaction rules")).toHaveLength(2);
    expect(screen.getAllByText("Monitors")).toHaveLength(2);

    // Trigger summaries
    expect(screen.getByText(/Cash transaction created/)).toBeInTheDocument();
    expect(screen.getByText(/Monitor · account/)).toBeInTheDocument();

    // Run stats: count, last-run badge, relative time
    expect(screen.getByText("3 runs")).toBeInTheDocument();
    expect(screen.getByText("completed")).toBeInTheDocument();
    expect(screen.getByText(/ago$/)).toBeInTheDocument();
  });

  it("filters by search text and clears back", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });
    await screen.findByText("Categorize coffee");

    fireEvent.change(screen.getByLabelText("Search workflows"), { target: { value: "balance" } });
    expect(screen.getByText("Balance monitor")).toBeInTheDocument();
    expect(screen.queryByText("Categorize coffee")).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Search workflows"), { target: { value: "" } });
    expect(await screen.findByText("Categorize coffee")).toBeInTheDocument();
  });

  it("filters by family tab and by status", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });
    await screen.findByText("Categorize coffee");

    // Family tab: monitors only
    await userEvent.click(screen.getByRole("tab", { name: /Monitors.*1/ }));
    expect(screen.getByText("Balance monitor")).toBeInTheDocument();
    expect(screen.queryByText("Categorize coffee")).not.toBeInTheDocument();

    // Back to all + paused-only status (w2 Balance monitor is inactive)
    await userEvent.click(screen.getByRole("tab", { name: /All.*2/ }));
    fireEvent.change(screen.getByLabelText("Filter by status"), { target: { value: "paused" } });
    expect(screen.getByText("Balance monitor")).toBeInTheDocument();
    expect(screen.queryByText("Categorize coffee")).not.toBeInTheDocument();
  });

  it("surfaces workflows whose last run failed under Needs attention", async () => {
    const failing = {
      ...WORKFLOWS[0], id: "w8", name: "Broken webhook",
      last_run_status: "failed", last_run_at: "2026-07-11T00:00:00Z",
    };
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/workflows") return [...WORKFLOWS, failing] as never;
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    expect(await screen.findByText("Needs attention")).toBeInTheDocument();
    expect(screen.getByText("Broken webhook")).toBeInTheDocument();
    expect(screen.getByText("failed")).toBeInTheDocument();
  });

  it("shows seeded workflows inline and filters by source", async () => {
    const nextAt = new Date(Date.now() + 3 * 3600e3).toISOString();
    const seeded = {
      id: "w3", name: "Market data sync", description: null,
      trigger_type: "schedule", trigger_config: { frequency: "daily", at: "05:00" },
      active: true, position: 0,
      seed_key: "market_data_sync", next_scheduled_at: nextAt, schedule_summary: "daily at 05:00",
      created_at: "2026-06-01T00:00:00Z", updated_at: "2026-06-01T00:00:00Z",
      run_count: 12, last_run_status: "completed", last_run_at: "2026-07-03T05:00:00Z",
    };
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/workflows") return [...WORKFLOWS, seeded] as never;
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    // All sources by default — seeded shows inline with a badge + schedule line.
    expect(await screen.findByText("Categorize coffee")).toBeInTheDocument();
    expect(screen.getByText("Market data sync")).toBeInTheDocument();
    expect(screen.getByText("system")).toBeInTheDocument();
    expect(screen.getByText(/daily at 05:00 · next in about 3 hours/)).toBeInTheDocument();

    // Source filter: system only.
    fireEvent.change(screen.getByLabelText("Filter by source"), { target: { value: "system" } });
    expect(screen.getByText("Market data sync")).toBeInTheDocument();
    expect(screen.queryByText("Categorize coffee")).not.toBeInTheDocument();

    // Source filter: mine only.
    fireEvent.change(screen.getByLabelText("Filter by source"), { target: { value: "mine" } });
    expect(screen.getByText("Categorize coffee")).toBeInTheDocument();
    expect(screen.queryByText("Market data sync")).not.toBeInTheDocument();
  });

  it("hides the delete button for seeded system workflows", async () => {
    const seeded = {
      ...WORKFLOWS[0], id: "w9", name: "System audit",
      trigger_type: "schedule", trigger_config: { frequency: "daily", at: "03:00" },
      seed_key: "system_audit", schedule_summary: "daily at 03:00",
    };
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/workflows") return [...WORKFLOWS, seeded] as never;
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    // Manual workflows keep their delete button.
    expect(await screen.findByRole("button", { name: "Delete Categorize coffee" })).toBeInTheDocument();

    expect(screen.getByText("System audit")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Delete System audit" })).not.toBeInTheDocument();
    // Run + history remain available on seeded rows.
    expect(screen.getByRole("button", { name: "Run System audit now" })).toBeInTheDocument();
  });

  it("renders the empty state when no workflows exist", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/workflows") return [] as never;
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    expect(await screen.findByText(/No workflows yet/i)).toBeInTheDocument();
  });
});

describe("Workflows: active toggle", () => {
  it("PATCHes /workflows/:id with the flipped active flag", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("switch", { name: "Deactivate Categorize coffee" }));
    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/workflows/w1", { active: false });
    });

    await userEvent.click(screen.getByRole("switch", { name: "Activate Balance monitor" }));
    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/workflows/w2", { active: true });
    });
  });
});

describe("Workflows: delete", () => {
  it("confirms then DELETEs the workflow", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: "Delete Categorize coffee" }));
    expect(await screen.findByText('Delete "Categorize coffee"?')).toBeInTheDocument();
    await userEvent.click(await screen.findByRole("button", { name: "Delete" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/workflows/w1");
    });
  });

  it("does not DELETE when the confirm is dismissed", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: "Delete Categorize coffee" }));
    await userEvent.click(await screen.findByRole("button", { name: "Cancel" }));
    expect(apiMock.delete).not.toHaveBeenCalled();
  });
});

describe("Workflows: navigation", () => {
  it("'New workflow' opens the editor", async () => {
    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    // "New workflow" lives in the page-actions menu in the header.
    await userEvent.setup().click(await screen.findByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /new workflow/i }));

    expect(await screen.findByPlaceholderText("Workflow name")).toBeInTheDocument();
    expect(screen.getByRole("heading", { level: 2, name: "New Workflow" })).toBeInTheDocument();
  });
});

describe("Run now from the list", () => {
  it("queues a run for the row's workflow after confirm", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/workflows") return WORKFLOWS as never;
      return [] as never;
    });
    apiMock.post.mockResolvedValue({ status: "queued", mode: "apply_to_existing" } as never);

    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /run categorize coffee now/i }));
    expect(await screen.findByText('Run "Categorize coffee" now?')).toBeInTheDocument();
    await userEvent.click(await screen.findByRole("button", { name: "Run" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows/w1/run_now", {});
    });
  });

  it("does not queue when confirm is dismissed", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/workflows") return WORKFLOWS as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows", initialToken: "tok" });

    await userEvent.click(await screen.findByRole("button", { name: /run categorize coffee now/i }));
    await userEvent.click(await screen.findByRole("button", { name: "Cancel" }));

    expect(apiMock.post).not.toHaveBeenCalled();
  });
});
