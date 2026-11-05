import { useState } from "react";
import { describe, it, expect, beforeEach, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { QuickAutomationModal } from "./QuickAutomationModal";
import { Toaster } from "@/components/ui/toast";
import type { CashTransaction } from "@/api/types";

const apiMock = vi.mocked(api);

const TX: CashTransaction = {
  id: "tx1",
  source: "plaid_sync",
  transaction_date: "2026-06-15",
  transfer_id: null,
  post_date: null,
  description: "STARBUCKS STORE #1234 SEATTLE WA",
  amount: -6.45,
  transaction_type: "DEBIT",
  category_id: "c1",
  category_name: "Coffee",
  merchant_id: "m1",
  merchant_name: "Starbucks",
  account_id: "a1",
  account_name: "Checking",
  balance: null,
  memo: null,
  loan_id: null,
  loan_name: null,
  tags: [],
  created_at: "2026-06-15T00:00:00Z",
};

const MERCHANTS = [
  { id: "m1", name: "Starbucks", category_id: "c1", category_name: "Coffee", notes: null, transaction_count: 10, excluded: false },
];
const CATEGORIES = [
  { id: "c1", name: "Coffee", parent_id: null, transaction_count: 10 },
];
const TAGS = [
  { id: "t1", name: "work" },
  { id: "t2", name: "travel" },
];

const CREATED_WORKFLOW = {
  id: "wf1", name: "Auto: STARBUCKS STORE #1234 SEATTLE", description: null,
  trigger_type: "cash_transaction.created", trigger_config: {}, active: true, position: 0,
  seed_key: null, next_scheduled_at: null, schedule_summary: null,
  created_at: "2026-07-03T00:00:00Z", updated_at: "2026-07-03T00:00:00Z",
  steps: [],
};

const MATCH_ROWS = [
  { ...TX, id: "p1", description: "STARBUCKS STORE #1234 SEATTLE WA", amount: -6.45 },
  { ...TX, id: "p2", description: "STARBUCKS STORE #9 PORTLAND OR", amount: -4.1 },
];

/** The payload the modal must POST for TX with its default (pre-filled) form.
 *  The name is "Auto: " + first 30 chars of the description, trimmed on save. */
const EXPECTED_PAYLOAD = {
  name: "Auto: STARBUCKS STORE #1234 SEATTLE",
  trigger_type: "cash_transaction.created",
  steps: [
    {
      kind: "branch",
      config: {
        match_all: true,
        conditions: [
          { field: "description", operator: "matches", value: "STARBUCKS STORE #1234 SEATTLE WA" },
          { field: "source", operator: "equals", value: "plaid_sync" },
        ],
      },
      children: [
        { kind: "action", config: { action_type: "assign_merchant", params: { merchant_id: "m1" } }, children: [] },
        { kind: "action", config: { action_type: "assign_category", params: { category_id: "c1" } }, children: [] },
      ],
    },
  ],
};

function ProbePage() {
  const location = useLocation();
  return <pre data-testid="probe-state">{JSON.stringify(location.state)}</pre>;
}

/** Unmounts the modal on close, like its real callers — an open Radix dialog
 * aria-hides the Toaster. */
function ClosableModal({ onClose, tx }: { onClose: () => void; tx: typeof TX }) {
  const [open, setOpen] = useState(true);
  return open ? <QuickAutomationModal tx={tx} onClose={() => { onClose(); setOpen(false); }} /> : null;
}

function renderModal(onClose = vi.fn(), tx = TX) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={["/transactions"]}>
        <Routes>
          <Route path="/transactions" element={<ClosableModal onClose={onClose} tx={tx} />} />
          <Route path="/workflows/new" element={<ProbePage />} />
          <Route path="/workflows/:id" element={<ProbePage />} />
        </Routes>
        <Toaster />
      </MemoryRouter>
    </QueryClientProvider>
  );
  return onClose;
}

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.post.mockReset();

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/merchants") return MERCHANTS as never;
    if (path === "/categories") return CATEGORIES as never;
    if (path === "/tags") return TAGS as never;
    return [] as never;
  });
  apiMock.post.mockImplementation(async (path: string) => {
    if (path === "/workflows") return CREATED_WORKFLOW as never;
    if (path === "/cash_transactions/filter") return { transactions: [], total: 0 } as never;
    return { status: "queued" } as never;
  });
});

/** Only the workflow-creation POSTs — the live preview also POSTs the filter endpoint. */
function workflowPosts() {
  return apiMock.post.mock.calls.filter(([path]) => String(path).startsWith("/workflows"));
}

describe("QuickAutomationModal: prefill", () => {
  it("renders name, conditions and action pickers pre-filled from the transaction", async () => {
    renderModal();

    // Name: "Auto: " + first 30 chars of the description (raw slice keeps the trailing space)
    expect(screen.getByLabelText("Name")).toHaveValue("Auto: STARBUCKS STORE #1234 SEATTLE ");

    // Condition rows, editable, pre-filled
    expect(screen.getByLabelText("Description matches")).toHaveValue("STARBUCKS STORE #1234 SEATTLE WA");
    expect(screen.getByLabelText("Source equals")).toHaveValue("plaid_sync");

    // Merchant and category comboboxes pre-select the transaction's values
    expect(await screen.findByDisplayValue("Starbucks")).toBeInTheDocument();
    expect(await screen.findByDisplayValue("Coffee")).toBeInTheDocument();

    // Tags offered as toggles; apply-to-existing defaults to on
    expect(await screen.findByRole("button", { name: "work" })).toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: "Apply to existing transactions" })).toBeChecked();
  });

  it("replaces * in the description prefill with a regex wildcard", () => {
    renderModal(vi.fn(), { ...TX, description: "SQ *BLUE BOTTLE*COFFEE" });

    expect(screen.getByLabelText("Description matches")).toHaveValue("SQ .BLUE BOTTLE.COFFEE");
  });

  it("allows removing a condition row", async () => {
    renderModal();

    await userEvent.click(screen.getByRole("button", { name: "Remove source condition" }));
    expect(screen.queryByLabelText("Source equals")).not.toBeInTheDocument();
    expect(screen.getByLabelText("Description matches")).toBeInTheDocument();
  });

  it("prefills a transfer action (name, row, payload) from transferAccount", async () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });
    render(
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={["/transactions"]}>
          <QuickAutomationModal
            tx={TX}
            transferAccount={{ id: "acc-schwab", name: "Schwab" }}
            onClose={vi.fn()}
          />
        </MemoryRouter>
      </QueryClientProvider>
    );

    expect(screen.getByLabelText("Name")).toHaveValue("Transfers to Schwab");
    expect(screen.getByText("Link as transfer")).toBeInTheDocument();
    expect(screen.getByText("Schwab")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Create automation" }));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", expect.objectContaining({
        name: "Transfers to Schwab",
        steps: [expect.objectContaining({
          children: [
            { kind: "action", config: { action_type: "transfer_to_account", params: { account_id: "acc-schwab" } }, children: [] },
          ],
        })],
      }));
    });
  });

  it("removing the transfer action row drops it from the payload", async () => {
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });
    render(
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={["/transactions"]}>
          <QuickAutomationModal
            tx={TX}
            transferAccount={{ id: "acc-schwab", name: "Schwab" }}
            onClose={vi.fn()}
          />
        </MemoryRouter>
      </QueryClientProvider>
    );

    await userEvent.click(screen.getByRole("button", { name: "Remove transfer action" }));
    expect(screen.queryByText("Link as transfer")).not.toBeInTheDocument();
    // With no remaining action the save button disables.
    expect(screen.getByRole("button", { name: "Create automation" })).toBeDisabled();
  });
});

describe("QuickAutomationModal: saving", () => {
  it("POSTs the exact workflow payload and applies to existing when checked", async () => {
    const onClose = renderModal();
    await screen.findByDisplayValue("Starbucks");

    await userEvent.click(screen.getByRole("button", { name: "Create automation" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", EXPECTED_PAYLOAD);
    });
    expect(apiMock.post).toHaveBeenCalledWith("/workflows/wf1/apply_to_existing", {});

    // No success screen: a toast confirms and the modal closes itself
    expect(await screen.findByRole("status")).toHaveTextContent(
      `Automation "${CREATED_WORKFLOW.name}" created — applying to existing transactions`
    );
    expect(onClose).toHaveBeenCalled();

    // The toast's action still reaches the new workflow
    await userEvent.click(screen.getByRole("button", { name: "View" }));
    await waitFor(() => expect(screen.queryByRole("status")).not.toBeInTheDocument());
    expect(screen.getByTestId("probe-state")).toBeInTheDocument();
  });

  it("skips apply_to_existing when the checkbox is unchecked", async () => {
    renderModal();
    await screen.findByDisplayValue("Starbucks");

    await userEvent.click(screen.getByRole("checkbox", { name: "Apply to existing transactions" }));
    await userEvent.click(screen.getByRole("button", { name: "Create automation" }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/workflows", EXPECTED_PAYLOAD);
    });
    expect(await screen.findByRole("status")).toHaveTextContent(`Automation "${CREATED_WORKFLOW.name}" created`);
    expect(screen.getByRole("status")).not.toHaveTextContent("applying to existing");
    expect(workflowPosts()).toHaveLength(1);
    expect(apiMock.post).not.toHaveBeenCalledWith("/workflows/wf1/apply_to_existing", {});
  });

  it("includes selected tags as an add_tag action", async () => {
    renderModal();
    await screen.findByDisplayValue("Starbucks");

    await userEvent.click(await screen.findByRole("button", { name: "work" }));
    await userEvent.click(screen.getByRole("button", { name: "Create automation" }));

    await waitFor(() => expect(workflowPosts().length).toBeGreaterThan(0));
    const [, payload] = workflowPosts()[0] as [string, typeof EXPECTED_PAYLOAD];
    expect(payload.steps[0].children).toContainEqual(
      { kind: "action", config: { action_type: "add_tag", params: { tag_id: ["t1"] } }, children: [] },
    );
  });

  it("disables saving when no action is selected", async () => {
    renderModal();
    await screen.findByDisplayValue("Starbucks");

    // Clear both pre-selected actions
    await userEvent.clear(screen.getByDisplayValue("Starbucks"));
    await userEvent.clear(screen.getByDisplayValue("Coffee"));

    expect(screen.getByRole("button", { name: "Create automation" })).toBeDisabled();
    expect(workflowPosts()).toHaveLength(0);
  });
});

describe("QuickAutomationModal: live match preview", () => {
  it("renders matched rows, the total pill and a '+N more' line", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/cash_transactions/filter") return { transactions: MATCH_ROWS, total: 142 } as never;
      return CREATED_WORKFLOW as never;
    });
    renderModal();

    expect(await screen.findByText("142 match")).toBeInTheDocument();
    expect(screen.getByText("STARBUCKS STORE #9 PORTLAND OR")).toBeInTheDocument();
    expect(screen.getByText("+140 more")).toBeInTheDocument();

    // The preview queries the workflow-parity filter endpoint with the current conditions
    expect(apiMock.post).toHaveBeenCalledWith("/cash_transactions/filter", {
      conditions: [
        { field: "description", operator: "matches", value: "STARBUCKS STORE #1234 SEATTLE WA" },
        { field: "source", operator: "equals", value: "plaid_sync" },
      ],
      match_all: true,
      limit: 8,
      count: true,
    }, { signal: expect.any(AbortSignal) });
  });

  it("tints the count pill red when the total is large (> 100)", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/cash_transactions/filter") return { transactions: MATCH_ROWS, total: 142 } as never;
      return CREATED_WORKFLOW as never;
    });
    renderModal();

    const pill = await screen.findByText("142 match");
    expect(pill.className).toContain("text-destructive");
  });

  it("uses the muted pill style for small totals", async () => {
    apiMock.post.mockImplementation(async (path: string) => {
      if (path === "/cash_transactions/filter") return { transactions: MATCH_ROWS, total: 2 } as never;
      return CREATED_WORKFLOW as never;
    });
    renderModal();

    const pill = await screen.findByText("2 match");
    expect(pill.className).not.toContain("text-destructive");
    expect(screen.queryByText(/more$/)).not.toBeInTheDocument();
  });

  it("shows the empty state when nothing matches", async () => {
    renderModal(); // default filter mock returns { transactions: [], total: 0 }

    expect(await screen.findByText("No transactions match")).toBeInTheDocument();
    expect(screen.getByText("0 match")).toBeInTheDocument();
  });

  it("refetches (debounced) when a condition value is edited", async () => {
    apiMock.post.mockImplementation(async (path: string, body?: unknown) => {
      if (path === "/cash_transactions/filter") {
        const value = (body as { conditions: { value: string }[] }).conditions[0]?.value;
        return (value === "COFFEE"
          ? { transactions: [{ ...TX, id: "p9", description: "COFFEE SHOP" }], total: 3 }
          : { transactions: MATCH_ROWS, total: 142 }) as never;
      }
      return CREATED_WORKFLOW as never;
    });
    renderModal();

    expect(await screen.findByText("142 match")).toBeInTheDocument();

    const input = screen.getByLabelText("Description matches");
    await userEvent.clear(input);
    await userEvent.type(input, "COFFEE");

    // Debounced ~350ms; the new result replaces the held-over previous list
    expect(await screen.findByText("3 match")).toBeInTheDocument();
    expect(screen.getByText("COFFEE SHOP")).toBeInTheDocument();
    expect(screen.queryByText("142 match")).not.toBeInTheDocument();
  });

  it("still queries with zero conditions (matches everything)", async () => {
    apiMock.post.mockImplementation(async (path: string, body?: unknown) => {
      if (path === "/cash_transactions/filter") {
        const conds = (body as { conditions: unknown[] }).conditions;
        return (conds.length === 0
          ? { transactions: MATCH_ROWS, total: 9999 }
          : { transactions: MATCH_ROWS, total: 142 }) as never;
      }
      return CREATED_WORKFLOW as never;
    });
    renderModal();
    await screen.findByText("142 match");

    await userEvent.click(screen.getByRole("button", { name: "Remove description condition" }));
    await userEvent.click(screen.getByRole("button", { name: "Remove source condition" }));

    expect(await screen.findByText("9,999 match")).toBeInTheDocument();
  });
});

describe("QuickAutomationModal: condition-less warning", () => {
  it("shows the warning only when the last condition row is removed, and keeps save enabled", async () => {
    renderModal();
    await screen.findByDisplayValue("Starbucks");

    const warning = /No conditions — this automation will apply to/;
    expect(screen.queryByText(warning)).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Remove description condition" }));
    expect(screen.queryByText(warning)).not.toBeInTheDocument(); // one row left

    await userEvent.click(screen.getByRole("button", { name: "Remove source condition" }));
    expect(screen.getByRole("alert")).toHaveTextContent(
      "No conditions — this automation will apply to every transaction."
    );
    expect(screen.getByRole("button", { name: "Create automation" })).toBeEnabled();
  });
});

describe("QuickAutomationModal: advanced handoff", () => {
  it("navigates to /workflows/new with state.prefill and closes the modal", async () => {
    const onClose = renderModal();

    await userEvent.click(screen.getByRole("button", { name: "Advanced" }));

    expect(onClose).toHaveBeenCalled();
    const state = JSON.parse(screen.getByTestId("probe-state").textContent ?? "{}");
    expect(state.prefill).toEqual(EXPECTED_PAYLOAD);
  });
});
