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

const ACCOUNT_FIELDS = {
  balance: { operators: ["greater_than", "less_than"] },
  name: { operators: ["contains", "equals"] },
};

const CATALOG = {
  triggers: [
    { type: "cash_transaction.created", subject_type: "CashTransaction", fields: TX_FIELDS },
    { type: "cash_transaction.updated", subject_type: "CashTransaction", fields: TX_FIELDS },
    { type: "account.updated", subject_type: "Account", fields: ACCOUNT_FIELDS },
    { type: "plaid.sync_completed", subject_type: "PlaidItem", fields: { status: { operators: ["equals"] } } },
    { type: "monitor", subject_type: null, fields: {} },
    { type: "schedule", subject_type: null, fields: {} },
  ],
  actions: ["assign_category", "set_memo", "notify", "fog_event"],
};

const SAVED_WORKFLOW = {
  id: "wf9", name: "Coffee flow", description: null,
  trigger_type: "cash_transaction.created", trigger_config: {}, active: true, position: 0,
  seed_key: null, next_scheduled_at: null, schedule_summary: null,
  created_at: "2026-07-01T00:00:00Z", updated_at: "2026-07-01T00:00:00Z",
  steps: [],
};

const EXISTING_WORKFLOW = {
  id: "w1", name: "Categorize coffee", description: "desc",
  trigger_type: "cash_transaction.created", trigger_config: {}, active: true, position: 0,
  seed_key: null, next_scheduled_at: null, schedule_summary: null,
  created_at: "2026-06-01T00:00:00Z", updated_at: "2026-06-01T00:00:00Z",
  steps: [
    {
      id: "s1", kind: "branch",
      config: { match_all: true, conditions: [{ field: "description", operator: "contains", value: "STARBUCKS" }] },
      children: [
        { id: "s2", kind: "action", config: { action_type: "set_memo", params: { value: "coffee" } }, children: [] },
      ],
    },
  ],
};

const SEEDED_WORKFLOW = {
  ...SAVED_WORKFLOW,
  id: "wsys", name: "System audit",
  trigger_type: "schedule", trigger_config: { frequency: "daily", at: "03:00" },
  seed_key: "system_audit", schedule_summary: "daily at 03:00",
};

/** Find the <select> whose options include the given option value. */
function selectWithOptionValue(value: string): HTMLSelectElement {
  const selects = screen.getAllByRole("combobox") as HTMLSelectElement[];
  const found = selects.find((s) => Array.from(s.options).some((o) => o.value === value));
  if (!found) throw new Error(`No select with option value "${value}"`);
  return found;
}

beforeEach(() => {
  clearToken();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  apiMock.post.mockResolvedValue(SAVED_WORKFLOW as never);
  apiMock.patch.mockResolvedValue(EXISTING_WORKFLOW as never);
  apiMock.delete.mockResolvedValue({} as never);

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return { user: { id: "u1", email: "x", name: "X" },
                                 household: { id: "h1", name: "H", role: "admin" } } as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/workflows/catalog") return CATALOG as never;
    if (path === "/workflows/wf9") return SAVED_WORKFLOW as never;
    if (path === "/workflows/w1") return EXISTING_WORKFLOW as never;
    if (path === "/workflows/wsys") return SEEDED_WORKFLOW as never;
    if (path === "/workflows") return [] as never;
    if (path === "/notifications") return { notifications: [], unread_count: 0 } as never;
    return [] as never;
  });
});

async function renderNewEditor() {
  renderApp({ initialPath: "/workflows/new", initialToken: "tok" });
  expect(await screen.findByPlaceholderText("Workflow name")).toBeInTheDocument();
}

describe("WorkflowEditor (create): building and saving a tree", () => {
  it("POSTs the full nested steps payload", async () => {
    await renderNewEditor();

    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Coffee flow");

    // Add a branch at the root and give it a condition.
    await userEvent.click(screen.getByRole("button", { name: "Branch" }));
    await userEvent.click(screen.getByRole("button", { name: /add condition/i }));
    await userEvent.type(screen.getByPlaceholderText("value"), "STARBUCKS");
    await userEvent.tab(); // blur commits the DeferredInput

    // Add an action inside the branch (the branch's add row renders before
    // the root's). Under load the branch's add row can commit a beat after
    // the click above — wait until both rows exist before indexing.
    await waitFor(() => {
      expect(screen.getAllByRole("button", { name: "Action" }).length).toBeGreaterThanOrEqual(2);
    });
    await userEvent.click(screen.getAllByRole("button", { name: "Action" })[0]);
    const actionSelect = selectWithOptionValue("notify");
    await userEvent.selectOptions(actionSelect, "notify");
    await userEvent.type(screen.getByPlaceholderText("Title"), "Coffee!");
    await userEvent.type(screen.getByPlaceholderText("Body"), "New coffee purchase");

    // Add a wait at the root (last add row) and set it to 2 hours.
    const waitButtons = screen.getAllByRole("button", { name: "Wait" });
    await userEvent.click(waitButtons[waitButtons.length - 1]);
    const duration = screen.getByLabelText("Wait duration");
    await userEvent.clear(duration);
    await userEvent.type(duration, "2");

    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", {
        name: "Coffee flow",
        description: null,
        trigger_type: "cash_transaction.created",
        active: true,
        trigger_config: {},
        steps: [
          {
            kind: "branch",
            config: {
              match_all: true,
              conditions: [{ field: "description", operator: "contains", value: "STARBUCKS" }],
            },
            children: [
              {
                kind: "action",
                config: { action_type: "notify", params: { title: "Coffee!", body: "New coffee purchase" } },
                children: [],
              },
            ],
          },
          { kind: "wait", config: { duration_seconds: 7200 }, children: [] },
        ],
      });
    });

    // Saving navigates to the edit view of the created workflow.
    expect(await screen.findByRole("heading", { level: 2, name: "Coffee flow" })).toBeInTheDocument();
  });

  it("keeps waits last among siblings when steps are added after them", async () => {
    await renderNewEditor();
    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Waits last");

    // Add a wait first, then an action at the root (the root add row renders
    // last, after the wait card's nested one) — the action must be submitted first.
    await userEvent.click(screen.getByRole("button", { name: "Wait" }));
    const actionButtons = screen.getAllByRole("button", { name: "Action" });
    await userEvent.click(actionButtons[actionButtons.length - 1]);

    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        steps: [
          { kind: "action", config: { action_type: "assign_category", params: {} }, children: [] },
          { kind: "wait", config: { duration_seconds: 3600 }, children: [] },
        ],
      }));
    });
  });

  it("surfaces API validation errors", async () => {
    apiMock.post.mockRejectedValueOnce(new Error("Name has already been taken"));
    await renderNewEditor();

    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Dup");
    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    expect(await screen.findByText("Name has already been taken")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { level: 2, name: "Coffee flow" })).not.toBeInTheDocument();
  });
});

describe("WorkflowEditor (create): trigger config", () => {
  it("an .updated trigger exposes a changed-fields multiselect saved as trigger_config", async () => {
    await renderNewEditor();

    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "On update");
    await userEvent.selectOptions(screen.getByLabelText("Trigger"), "cash_transaction.updated");

    expect(await screen.findByText(/Only run when one of these fields changed/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "description" }));

    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        trigger_type: "cash_transaction.updated",
        trigger_config: { changed_fields: ["description"] },
      }));
    });
  });

  it("a monitor trigger exposes subject + conditions saved as trigger_config", async () => {
    await renderNewEditor();

    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Low balance");
    await userEvent.selectOptions(screen.getByLabelText("Trigger"), "monitor");

    // Subject picker defaults to the first record model; switch to account.
    const subjectSelect = selectWithOptionValue("account");
    await userEvent.selectOptions(subjectSelect, "account");

    // Condition editor uses the account.updated catalog fields.
    await userEvent.click(screen.getByRole("button", { name: /add condition/i }));
    await userEvent.type(screen.getByPlaceholderText("value"), "1000");
    await userEvent.tab();

    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        trigger_type: "monitor",
        trigger_config: {
          subject: "account",
          match_all: true,
          conditions: [{ field: "balance", operator: "greater_than", value: "1000" }],
        },
      }));
    });
  });
});

describe("WorkflowEditor: seeded system workflows", () => {
  it("hides the delete action for seeded workflows, keeps it for manual ones", async () => {
    renderApp({ initialPath: "/workflows/wsys", initialToken: "tok" });
    expect(await screen.findByPlaceholderText("Workflow name")).toHaveValue("System audit");

    // The page-actions menu still offers Run now / View runs, but no delete.
    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    expect(await screen.findByRole("menuitem", { name: "Run now" })).toBeInTheDocument();
    expect(screen.queryByRole("menuitem", { name: "Delete workflow" })).not.toBeInTheDocument();
  });

  it("still offers delete on a manual workflow", async () => {
    renderApp({ initialPath: "/workflows/w1", initialToken: "tok" });
    expect(await screen.findByPlaceholderText("Workflow name")).toHaveValue("Categorize coffee");

    await userEvent.setup().click(screen.getByRole("button", { name: /Page actions/i }));
    expect(await screen.findByRole("menuitem", { name: "Delete workflow" })).toBeInTheDocument();
  });
});

describe("WorkflowEditor: schedule trigger", () => {
  it("saves a daily schedule as {frequency, at}", async () => {
    await renderNewEditor();
    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Nightly sync");
    await userEvent.selectOptions(screen.getByLabelText("Trigger"), "schedule");

    // Daily is the default frequency; set the time.
    fireEvent.change(screen.getByLabelText("Time"), { target: { value: "07:15" } });

    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        trigger_type: "schedule",
        trigger_config: { frequency: "daily", at: "07:15" },
      }));
    });
  });

  it("saves a weekly schedule as {frequency, at, day_of_week}", async () => {
    await renderNewEditor();
    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Weekly digest");
    await userEvent.selectOptions(screen.getByLabelText("Trigger"), "schedule");

    await userEvent.selectOptions(screen.getByLabelText("Frequency"), "weekly");
    await userEvent.selectOptions(screen.getByLabelText("Day of week"), "5"); // Friday
    fireEvent.change(screen.getByLabelText("Time"), { target: { value: "06:30" } });

    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        trigger_type: "schedule",
        trigger_config: { frequency: "weekly", at: "06:30", day_of_week: 5 },
      }));
    });
  });

  it("saves an hourly schedule as {frequency, every_hours}", async () => {
    await renderNewEditor();
    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Frequent sync");
    await userEvent.selectOptions(screen.getByLabelText("Trigger"), "schedule");

    await userEvent.selectOptions(screen.getByLabelText("Frequency"), "hourly");
    fireEvent.change(screen.getByLabelText("Every N hours"), { target: { value: "4" } });

    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        trigger_type: "schedule",
        trigger_config: { frequency: "hourly", every_hours: 4 },
      }));
    });
  });

  it("shows the data-actions-skipped hint instead of the amber warning", async () => {
    await renderNewEditor();
    await userEvent.selectOptions(screen.getByLabelText("Trigger"), "schedule");

    // No data actions yet — no hint.
    expect(screen.queryByText(/data actions will be skipped/)).not.toBeInTheDocument();

    // An unguarded data action would normally raise the amber warning; on a
    // schedule it becomes the muted skip hint instead.
    await userEvent.click(screen.getByRole("button", { name: "Action" }));
    expect(screen.getByText("Scheduled runs have no subject — data actions will be skipped.")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });
});

describe("WorkflowEditor: unguarded data-change warning", () => {
  const WARNING = /no conditions guarding its data changes/;

  it("warns when a data action sits outside any branch with conditions", async () => {
    await renderNewEditor();
    expect(screen.queryByText(WARNING)).not.toBeInTheDocument();

    // Root-level action defaults to assign_category — a data action with no guard.
    await userEvent.click(screen.getByRole("button", { name: "Action" }));

    expect(screen.getByRole("alert")).toHaveTextContent(
      "This workflow has no conditions guarding its data changes — it will modify every cash transaction that triggers it."
    );

    // Save stays enabled (warn only)
    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Risky");
    expect(screen.getByRole("button", { name: /create workflow/i })).toBeEnabled();
  });

  it("offers fog_event as \"send to HUD\" and saves its params", async () => {
    await renderNewEditor();
    await userEvent.type(screen.getByPlaceholderText("Workflow name"), "Coffee flow");

    await userEvent.click(screen.getByRole("button", { name: "Action" }));
    const actionSelect = selectWithOptionValue("fog_event");
    expect(screen.getByRole("option", { name: "send to HUD" })).toBeInTheDocument();
    await userEvent.selectOptions(actionSelect, "fog_event");
    await userEvent.type(screen.getByPlaceholderText("Title (defaults to the workflow name)"), "Coffee!");
    await userEvent.type(screen.getByPlaceholderText("Key (optional)"), "coffee");

    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        steps: [expect.objectContaining({
          kind: "action",
          config: expect.objectContaining({ action_type: "fog_event", params: { title: "Coffee!", key: "coffee" } }),
        })],
      }));
    });
  });

  it("does not warn for side-effect-only actions (notify)", async () => {
    await renderNewEditor();

    await userEvent.click(screen.getByRole("button", { name: "Action" }));
    expect(screen.getByText(WARNING)).toBeInTheDocument();

    await userEvent.selectOptions(selectWithOptionValue("notify"), "notify");
    expect(screen.queryByText(WARNING)).not.toBeInTheDocument();
  });

  it("clears the warning once the action is guarded by a branch with conditions", async () => {
    await renderNewEditor();

    // Branch (no conditions yet) with an action inside → still unguarded.
    await userEvent.click(screen.getByRole("button", { name: "Branch" }));
    await userEvent.click(screen.getAllByRole("button", { name: "Action" })[0]);
    expect(screen.getByText(WARNING)).toBeInTheDocument();

    // Adding a condition to the branch guards the action.
    await userEvent.click(screen.getByRole("button", { name: /add condition/i }));
    expect(screen.queryByText(WARNING)).not.toBeInTheDocument();
  });

  it("does not warn when an existing workflow's data action is under a conditioned branch", async () => {
    renderApp({ initialPath: "/workflows/w1", initialToken: "tok" });

    expect(await screen.findByPlaceholderText("Workflow name")).toHaveValue("Categorize coffee");
    // set_memo is a data action, but it sits under a branch with a condition.
    expect(screen.queryByText(WARNING)).not.toBeInTheDocument();
  });
});

describe("WorkflowEditor (create): router-state prefill", () => {
  const PREFILL = {
    name: "Auto: STARBUCKS",
    trigger_type: "account.updated",
    steps: [
      {
        kind: "branch",
        config: { match_all: true, conditions: [{ field: "name", operator: "contains", value: "Chase" }] },
        children: [
          { kind: "action", config: { action_type: "set_memo", params: { value: "coffee" } }, children: [] },
        ],
      },
    ],
  };

  it("initializes the draft from location.state.prefill", async () => {
    renderApp({
      initialPath: { pathname: "/workflows/new", state: { prefill: PREFILL } },
      initialToken: "tok",
    });

    // Name, trigger and steps all come from the prefill
    expect(await screen.findByPlaceholderText("Workflow name")).toHaveValue("Auto: STARBUCKS");
    expect(screen.getByLabelText("Trigger")).toHaveValue("account.updated");
    expect(screen.getByDisplayValue("Chase")).toBeInTheDocument();
    expect(screen.getByDisplayValue("coffee")).toBeInTheDocument();

    // Saving submits the prefilled tree unchanged
    await userEvent.click(screen.getByRole("button", { name: /create workflow/i }));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        name: "Auto: STARBUCKS",
        trigger_type: "account.updated",
        steps: PREFILL.steps,
      }));
    });
  });

  it("ignores prefill when editing an existing workflow", async () => {
    renderApp({
      initialPath: { pathname: "/workflows/w1", state: { prefill: PREFILL } },
      initialToken: "tok",
    });

    expect(await screen.findByPlaceholderText("Workflow name")).toHaveValue("Categorize coffee");
    expect(screen.getByLabelText("Trigger")).toHaveValue("cash_transaction.created");
  });
});

describe("WorkflowEditor (edit): loading and saving", () => {
  it("renders the existing tree and PATCHes the whole tree on save", async () => {
    renderApp({ initialPath: "/workflows/w1", initialToken: "tok" });

    expect(await screen.findByRole("heading", { level: 2, name: "Categorize coffee" })).toBeInTheDocument();
    // The branch condition and nested action loaded into the builder.
    expect(screen.getByDisplayValue("STARBUCKS")).toBeInTheDocument();
    expect(screen.getByPlaceholderText("Memo text")).toHaveValue("coffee");

    await userEvent.type(screen.getByPlaceholderText("Workflow name"), " v2");
    await userEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/workflows/w1", {
        name: "Categorize coffee v2",
        description: "desc",
        trigger_type: "cash_transaction.created",
        active: true,
        trigger_config: {},
        steps: [
          {
            kind: "branch",
            config: { match_all: true, conditions: [{ field: "description", operator: "contains", value: "STARBUCKS" }] },
            children: [
              { kind: "action", config: { action_type: "set_memo", params: { value: "coffee" } }, children: [] },
            ],
          },
        ],
      });
    });
  });

  it("toggling a branch to else drops its conditions from the payload", async () => {
    renderApp({ initialPath: "/workflows/w1", initialToken: "tok" });
    expect(await screen.findByDisplayValue("STARBUCKS")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("checkbox", { name: /else branch/i }));
    expect(screen.getByText(/Runs when no earlier branch matched/)).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/workflows/w1", expect.objectContaining({
        steps: [expect.objectContaining({ kind: "branch", config: { else: true } })],
      }));
    });
  });
});

describe("Run now", () => {
  beforeEach(() => {
    clearToken();
    vi.restoreAllMocks();
  });

  it("queues a manual run from the editor header after confirm", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/workflows/catalog") return CATALOG as never;
      if (path === "/workflows/w1") return EXISTING_WORKFLOW as never;
      return [] as never;
    });
    apiMock.post.mockResolvedValue({ status: "queued", mode: "apply_to_existing" } as never);

    renderApp({ initialPath: "/workflows/w1", initialToken: "tok" });
    const user = userEvent.setup();

    // "Run now" lives in the page-actions menu in the header.
    await user.click(await screen.findByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Run now" }));
    expect(await screen.findByText("Run this workflow now?")).toBeInTheDocument();
    await user.click(await screen.findByRole("button", { name: "Run" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows/w1/run_now", {});
    });
    expect(await screen.findByText(/run queued/i)).toBeInTheDocument();
  });

  it("does not queue when the confirm is dismissed", async () => {
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/workflows/catalog") return CATALOG as never;
      if (path === "/workflows/w1") return EXISTING_WORKFLOW as never;
      return [] as never;
    });

    renderApp({ initialPath: "/workflows/w1", initialToken: "tok" });
    const user = userEvent.setup();

    await user.click(await screen.findByRole("button", { name: /Page actions/i }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Run now" }));
    await user.click(await screen.findByRole("button", { name: "Cancel" }));

    expect(apiMock.post).not.toHaveBeenCalled();
  });
});
