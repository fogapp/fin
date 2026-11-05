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

const WORKFLOW = {
  id: "w1", name: "Categorize coffee", description: null,
  trigger_type: "cash_transaction.created", trigger_config: {}, active: true, position: 0,
  created_at: "2026-06-01T00:00:00Z", updated_at: "2026-06-01T00:00:00Z",
  steps: [],
};

const RUNS = {
  runs: [
    {
      id: "r1", workflow_id: "w1", workflow_name: "Categorize coffee",
      event_type: "cash_transaction.created", event_payload: {},
      subject_type: "CashTransaction", subject_id: "tx1",
      status: "completed", error: null,
      started_at: "2026-07-01T12:00:00Z", finished_at: "2026-07-01T12:00:01Z",
      reverted_at: null, revertible: true,
      created_at: "2026-07-01T12:00:00Z",
    },
    {
      id: "r2", workflow_id: "w1", workflow_name: "Categorize coffee",
      event_type: "cash_transaction.created", event_payload: {},
      subject_type: "CashTransaction", subject_id: "tx2",
      status: "failed", error: "webhook returned 500",
      started_at: "2026-07-01T13:00:00Z", finished_at: "2026-07-01T13:00:02Z",
      reverted_at: null, revertible: false,
      created_at: "2026-07-01T13:00:00Z",
    },
    {
      id: "r3", workflow_id: "w1", workflow_name: "Categorize coffee",
      event_type: "cash_transaction.created", event_payload: {},
      subject_type: "CashTransaction", subject_id: "tx3",
      status: "cancelled", error: null,
      started_at: "2026-07-01T14:00:00Z", finished_at: "2026-07-01T14:00:01Z",
      reverted_at: "2026-07-02T09:00:00Z", revertible: false,
      created_at: "2026-07-01T14:00:00Z",
    },
  ],
  meta: { page: 1, per_page: 50, total: 3 },
};

const group = (traceId: string, run: (typeof RUNS.runs)[number], statuses: Record<string, number>, reverted = 0) => ({
  trace_id: traceId, workflow_id: "w1", workflow_name: "Categorize coffee",
  event_type: run.event_type, count: 1, statuses, reverted,
  first_at: run.created_at, last_at: run.created_at, run,
});

const GROUPS = {
  groups: [
    group("t1", RUNS.runs[0], { completed: 1 }),
    group("t2", RUNS.runs[1], { failed: 1 }),
    group("t3", RUNS.runs[2], { cancelled: 1 }, 1),
    {
      trace_id: "t4", workflow_id: "w1", workflow_name: "Categorize coffee",
      event_type: "manual.apply_to_existing", count: 788,
      statuses: { completed: 742, failed: 46 }, reverted: 12,
      first_at: "2026-06-30T10:00:00Z", last_at: "2026-06-30T10:05:00Z", run: null,
    },
  ],
  meta: { page: 1, per_page: 30, total: 4 },
};

const traceRun = (id: string, txId: string) => ({
  id, workflow_id: "w1", workflow_name: "Categorize coffee",
  event_type: "manual.apply_to_existing", event_payload: {},
  subject_type: "CashTransaction", subject_id: txId,
  status: "completed", error: null,
  started_at: "2026-06-30T10:00:00Z", finished_at: "2026-06-30T10:00:01Z",
  reverted_at: null, revertible: true,
  created_at: "2026-06-30T10:00:00Z",
});

const TRACE_RUNS_P1 = {
  runs: [traceRun("m1", "mtx1"), traceRun("m2", "mtx2")],
  meta: { page: 1, per_page: 50, total: 788 },
};

const TRACE_RUNS_P2 = {
  runs: [traceRun("m3", "mtx3")],
  meta: { page: 2, per_page: 50, total: 788 },
};

const RUN_DETAIL = {
  ...RUNS.runs[0],
  steps: [
    { id: "rs1", step_id: "s1", step_kind: "branch", status: "matched", output: {}, resume_at: null, created_at: "2026-07-01T12:00:00Z" },
    { id: "rs2", step_id: "s2", step_kind: "action", status: "applied", output: { category_id: "c9" }, resume_at: null, created_at: "2026-07-01T12:00:01Z" },
    { id: "rs3", step_id: "s3", step_kind: "wait", status: "waiting", output: {}, resume_at: "2027-01-01T00:00:00Z", created_at: "2026-07-01T12:00:01Z" },
  ],
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
    if (path === "/workflows/w1") return WORKFLOW as never;
    if (path.startsWith("/workflow_runs/")) return RUN_DETAIL as never;
    if (path.includes("grouped=true")) return GROUPS as never;
    if (path.includes("trace_id=t4")) return (path.includes("page=2") ? TRACE_RUNS_P2 : TRACE_RUNS_P1) as never;
    if (path.startsWith("/workflow_runs")) return RUNS as never;
    if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
    return [] as never;
  });
});

describe("WorkflowRunsPage: list", () => {
  it("renders the run list scoped to the workflow with status badges", async () => {
    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });

    expect(await screen.findByRole("heading", { level: 2, name: /Runs/ })).toBeInTheDocument();
    expect(await screen.findByText("Categorize coffee")).toBeInTheDocument();

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/workflow_runs?workflow_id=w1&grouped=true&page=1");
    });

    expect(screen.getByText("completed")).toBeInTheDocument();
    expect(screen.getByText("failed")).toBeInTheDocument();
    expect(screen.getByText(/CashTransaction tx1/)).toBeInTheDocument();
  });

  it("re-fetches with the selected status filter", async () => {
    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });
    expect(await screen.findByText("completed")).toBeInTheDocument();

    await userEvent.selectOptions(screen.getByRole("combobox"), "failed");

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/workflow_runs?workflow_id=w1&status=failed&grouped=true&page=1");
    });
  });
});

describe("WorkflowRunsPage: step detail", () => {
  it("expanding a run fetches and renders step-level detail", async () => {
    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });

    // Header dropdown triggers also carry aria-expanded, so target r1's row by name.
    const row = await screen.findByRole("button", { name: /CashTransaction tx1/, expanded: false });
    await userEvent.click(row);

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/workflow_runs/r1");
    });

    // Step kinds and statuses
    expect(await screen.findByText("branch")).toBeInTheDocument();
    expect(screen.getByText("action")).toBeInTheDocument();
    expect(screen.getByText("wait")).toBeInTheDocument();
    expect(screen.getByText("matched")).toBeInTheDocument();
    expect(screen.getByText("applied")).toBeInTheDocument();
    expect(screen.getByText("waiting")).toBeInTheDocument();

    // Output JSON and resume_at
    expect(screen.getByText(/"category_id": "c9"/)).toBeInTheDocument();
    expect(screen.getByText(/resumes in/)).toBeInTheDocument();
  });

  it("an expanded failed run shows its error", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                   household: { id: "h1", name: "H", role: "admin" } } as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/workflows/w1") return WORKFLOW as never;
      if (path === "/workflow_runs/r2") return { ...RUNS.runs[1], steps: [] } as never;
      if (path.includes("grouped=true")) return GROUPS as never;
      if (path.startsWith("/workflow_runs")) return RUNS as never;
      if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });

    const row = await screen.findByRole("button", { name: /CashTransaction tx2/, expanded: false });
    await userEvent.click(row);

    expect(await screen.findByText("webhook returned 500")).toBeInTheDocument();
    expect(screen.getByText(/No step executions recorded/)).toBeInTheDocument();
  });
});

describe("WorkflowRunsPage: grouped", () => {
  it("renders multi-run traces as a group row and single-run traces as plain rows", async () => {
    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });

    // Multi-run group: count, humanized event label, status summary, reverted count
    expect(await screen.findByText(/788 runs · Manual run/)).toBeInTheDocument();
    expect(screen.getByText("742 completed")).toBeInTheDocument();
    expect(screen.getByText("46 failed")).toHaveClass("text-destructive");
    expect(screen.getByText(/12 reverted/)).toBeInTheDocument();

    // Time range title shows first → last
    const groupButton = screen.getByRole("button", { name: /788 runs/ });
    expect(groupButton.querySelector("[title*='→']")).not.toBeNull();

    // Single-run groups render as ordinary run rows
    expect(screen.getByText(/CashTransaction tx1/)).toBeInTheDocument();
    expect(screen.getByText(/CashTransaction tx2/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Revert run r1" })).toBeInTheDocument();
  });

  it("expanding a group fetches by trace_id, nests run rows, loads more, and collapses", async () => {
    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });

    const groupButton = await screen.findByRole("button", { name: /788 runs/ });
    await userEvent.click(groupButton);

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/workflow_runs?workflow_id=w1&trace_id=t4&page=1");
    });
    expect(await screen.findByText(/CashTransaction mtx1/)).toBeInTheDocument();
    expect(screen.getByText(/CashTransaction mtx2/)).toBeInTheDocument();

    // Group exceeds one page of 50 → Load more appends the next page
    await userEvent.click(screen.getByRole("button", { name: "Load more" }));
    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/workflow_runs?workflow_id=w1&trace_id=t4&page=2");
    });
    expect(await screen.findByText(/CashTransaction mtx3/)).toBeInTheDocument();
    expect(screen.getByText(/CashTransaction mtx1/)).toBeInTheDocument();

    // Second click collapses
    await userEvent.click(groupButton);
    expect(screen.queryByText(/CashTransaction mtx1/)).not.toBeInTheDocument();
  });
});

describe("WorkflowRunsPage: revert", () => {
  it("shows a Revert button only on revertible runs and a badge on reverted ones", async () => {
    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });
    expect(await screen.findByText("completed")).toBeInTheDocument();

    expect(screen.getByRole("button", { name: "Revert run r1" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Revert run r2" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Revert run r3" })).not.toBeInTheDocument();

    const badge = screen.getByText("reverted");
    expect(badge).toHaveAttribute("title", expect.stringContaining("Reverted"));
  });

  it("confirming a revert POSTs and shows the restored/kept counts", async () => {
    apiMock.post.mockResolvedValue({ status: "reverted", reverted: 3, conflicted: 1, skipped: 0 } as never);

    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });
    await userEvent.click(await screen.findByRole("button", { name: "Revert run r1" }));
    expect(await screen.findByText("Revert this run?")).toBeInTheDocument();
    await userEvent.click(await screen.findByRole("button", { name: "Revert" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflow_runs/r1/revert", {});
    });
    expect(await screen.findByText("3 changes restored, 1 kept — changed since")).toBeInTheDocument();
  });

  it("does not POST when the revert confirm is dismissed", async () => {
    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });
    await userEvent.click(await screen.findByRole("button", { name: "Revert run r1" }));
    await userEvent.click(await screen.findByRole("button", { name: "Cancel" }));

    expect(apiMock.post).not.toHaveBeenCalled();
  });

  it("'Revert all runs' confirms then POSTs to the bulk endpoint and shows a queued notice", async () => {
    apiMock.post.mockResolvedValue({ status: "queued" } as never);

    renderApp({ initialPath: "/workflows/w1/runs", initialToken: "tok" });

    // "Revert all runs" is a destructive item in the page-actions menu.
    await userEvent.setup().click(await screen.findByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: /Revert all runs/ }));

    expect(await screen.findByText("Revert all runs of this workflow?")).toBeInTheDocument();
    expect(screen.getByText(/cannot be undone/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Revert" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows/w1/revert_runs", {});
    });
    expect(await screen.findByText(/Revert queued/)).toBeInTheDocument();
  });
});
