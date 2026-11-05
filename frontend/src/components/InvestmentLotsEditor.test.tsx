import { describe, it, expect, beforeEach } from "vitest";
import { screen, fireEvent, waitFor } from "@testing-library/react";
import { vi } from "vitest";
import { renderWithClient } from "@/test/queryClient";
import type { InvestmentLot, Account } from "@/api/types";

vi.mock("@/api/client", () => ({ api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() } }));

import { api } from "@/api/client";
import { InvestmentLotsEditor } from "./InvestmentLotsEditor";
import { emptyForm, lotToForm, parseDecimal } from "@/lib/lotForm";

const mockedApi = vi.mocked(api);

describe("InvestmentLotsEditor — helpers", () => {
  describe("emptyForm", () => {
    it("returns a fully-blank form", () => {
      expect(emptyForm()).toEqual({
        account_id: "", acquired_date: "", quantity: "", cost_basis: "", notes: "",
      });
    });
  });

  describe("lotToForm", () => {
    it("converts an InvestmentLot to a form-shape with strings", () => {
      const form = lotToForm({
        id: "l1", security_id: "sec-1", account_id: "acc-1",
        account_name: "Brokerage", acquired_date: "2026-01-15",
        quantity: 10, cost_basis: 1500, unit_cost: 150, notes: "buy 1",
      } as never);
      expect(form).toEqual({
        account_id: "acc-1", acquired_date: "2026-01-15",
        quantity: "10", cost_basis: "1500", notes: "buy 1",
      });
    });

    it("normalizes null account_id, acquired_date, and notes to empty strings", () => {
      const form = lotToForm({
        id: "l1", security_id: "sec-1", account_id: null,
        account_name: null, acquired_date: null,
        quantity: 5, cost_basis: 100, unit_cost: 20, notes: null,
      } as never);
      expect(form).toEqual({
        account_id: "", acquired_date: "", quantity: "5", cost_basis: "100", notes: "",
      });
    });
  });

  describe("parseDecimal", () => {
    it.each([
      [ "1234.56", 1234.56 ],
      [ "$1,500.00", 1500 ],
      [ "0", 0 ],
      [ "-42.5", -42.5 ],
    ])("parses %s → %s", (input, expected) => {
      expect(parseDecimal(input)).toBe(expected);
    });

    it("returns null for non-numeric strings", () => {
      expect(parseDecimal("")).toBeNull();
      expect(parseDecimal("not a number")).toBeNull();
    });
  });
});

describe("InvestmentLotsEditor — smoke", () => {
  it("renders without crashing and shows a header row", () => {
    renderWithClient(
      <InvestmentLotsEditor
        securityId="sec-1"
        lots={[
          {
            id: "l1", security_id: "sec-1", account_id: "acc-1",
            account_name: "Brokerage", acquired_date: "2026-01-15",
            quantity: 10, cost_basis: 1500, unit_cost: 150, notes: null,
          } as never,
        ]}
        accounts={[ { id: "acc-1", name: "Brokerage" } as never ]}
        onChanged={() => {}}
      />,
    );
    // The table header row labels
    expect(screen.getByText(/Account/i)).toBeInTheDocument();
    expect(screen.getByText(/Acquired/i)).toBeInTheDocument();
    expect(screen.getByText(/Quantity/i)).toBeInTheDocument();
    expect(screen.getByText(/Cost basis/i)).toBeInTheDocument();
    expect(screen.getByText(/Unit cost/i)).toBeInTheDocument();
  });

  it("renders one row per lot", () => {
    renderWithClient(
      <InvestmentLotsEditor
        securityId="sec-1"
        lots={[
          { id: "l1", security_id: "sec-1", account_id: "acc-1", account_name: "Brokerage", acquired_date: "2026-01-15", quantity: 10, cost_basis: 1500, unit_cost: 150, notes: null } as never,
          { id: "l2", security_id: "sec-1", account_id: "acc-1", account_name: "Brokerage", acquired_date: "2026-03-01", quantity: 5,  cost_basis: 800,  unit_cost: 160, notes: null } as never,
        ]}
        accounts={[ { id: "acc-1", name: "Brokerage" } as never ]}
        onChanged={() => {}}
      />,
    );
    expect(screen.getAllByText(/Brokerage/).length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("$1,500.00")).toBeInTheDocument();
    expect(screen.getByText("$800.00")).toBeInTheDocument();
  });
});

// ── Interaction tests ─────────────────────────────────────────────────────────

const accounts = [{ id: "acc-1", name: "Brokerage" }] as unknown as Account[];

function makeLot(overrides: Partial<InvestmentLot> = {}): InvestmentLot {
  return {
    id: "l1",
    security_id: "sec-1",
    account_id: "acc-1",
    account_name: "Brokerage",
    acquired_date: "2026-01-15",
    quantity: 10,
    cost_basis: 1500,
    unit_cost: 150,
    notes: null,
    ...overrides,
  } as InvestmentLot;
}

/** The green ✓ commit button of the currently-editing row. */
function commitButton(container: HTMLElement): HTMLElement {
  const btn = container.querySelector<HTMLElement>("button.text-positive");
  if (!btn) throw new Error("commit button not found");
  return btn;
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("InvestmentLotsEditor — empty state & totals", () => {
  it("shows an empty state when there are no lots", () => {
    renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={() => {}} />,
    );
    expect(screen.getByText(/No lots defined yet/)).toBeInTheDocument();
  });

  it("shows quantity and cost-basis totals when there are 2+ lots", () => {
    renderWithClient(
      <InvestmentLotsEditor
        securityId="sec-1"
        lots={[makeLot(), makeLot({ id: "l2", quantity: 5, cost_basis: 800 })]}
        accounts={accounts}
        onChanged={() => {}}
      />,
    );
    expect(screen.getByText("Total (2 lots)")).toBeInTheDocument();
    expect(screen.getByText("15")).toBeInTheDocument();       // 10 + 5
    expect(screen.getByText("$2,300.00")).toBeInTheDocument(); // 1500 + 800
  });
});

describe("InvestmentLotsEditor — adding a lot", () => {
  it("POSTs the parsed form and appends the created lot", async () => {
    const created = makeLot({ id: "l-new", quantity: 4, cost_basis: 600, notes: "spring buy" });
    mockedApi.post.mockResolvedValue(created);
    const onChanged = vi.fn();
    const { container } = renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={onChanged} />,
    );

    fireEvent.click(screen.getByRole("button", { name: /Add lot/ }));
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "acc-1" } });
    fireEvent.change(container.querySelector('input[type="date"]')!, { target: { value: "2026-04-01" } });
    fireEvent.change(screen.getByPlaceholderText("0"), { target: { value: "4" } });
    fireEvent.change(screen.getByPlaceholderText("0.00"), { target: { value: "600" } });
    fireEvent.change(screen.getByPlaceholderText("Notes…"), { target: { value: "spring buy" } });

    // Computed unit cost preview: 600 / 4
    expect(screen.getByText("$150.00")).toBeInTheDocument();

    fireEvent.click(commitButton(container));
    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith("/investment_lots", {
        security_id: "sec-1",
        account_id: "acc-1",
        acquired_date: "2026-04-01",
        quantity: 4,
        cost_basis: 600,
        notes: "spring buy",
      });
    });
    await waitFor(() => expect(onChanged).toHaveBeenCalledWith([created]));
  });

  it("nullifies optional fields left blank", async () => {
    mockedApi.post.mockResolvedValue(makeLot({ id: "l-new" }));
    const { container } = renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={() => {}} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /Add lot/ }));
    fireEvent.change(screen.getByPlaceholderText("0"), { target: { value: "2" } });
    fireEvent.change(screen.getByPlaceholderText("0.00"), { target: { value: "100" } });
    fireEvent.click(commitButton(container));
    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith("/investment_lots", {
        security_id: "sec-1",
        account_id: null,
        acquired_date: null,
        quantity: 2,
        cost_basis: 100,
        notes: null,
      });
    });
  });

  it("validates that quantity and cost basis are required", () => {
    const { container } = renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={() => {}} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /Add lot/ }));
    fireEvent.click(commitButton(container));
    expect(screen.getByText("Quantity and cost basis are required.")).toBeInTheDocument();
    expect(mockedApi.post).not.toHaveBeenCalled();

    fireEvent.change(screen.getByPlaceholderText("0"), { target: { value: "3" } });
    fireEvent.click(commitButton(container));
    expect(screen.getByText("Cost basis is required.")).toBeInTheDocument();
    expect(mockedApi.post).not.toHaveBeenCalled();
  });

  it("shows the server error message when the create fails", async () => {
    mockedApi.post.mockRejectedValue(new Error("Quantity must be positive"));
    const { container } = renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={() => {}} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /Add lot/ }));
    fireEvent.change(screen.getByPlaceholderText("0"), { target: { value: "1" } });
    fireEvent.change(screen.getByPlaceholderText("0.00"), { target: { value: "10" } });
    fireEvent.click(commitButton(container));
    expect(await screen.findByText("Quantity must be positive")).toBeInTheDocument();
  });

  it("cancels the add row without saving", () => {
    renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={() => {}} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /Add lot/ }));
    expect(screen.queryByRole("button", { name: /Add lot/ })).toBeNull(); // footer hidden while adding

    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.getByRole("button", { name: /Add lot/ })).toBeInTheDocument();
    expect(mockedApi.post).not.toHaveBeenCalled();
  });
});

describe("InvestmentLotsEditor — editing a lot", () => {
  it("PATCHes the lot and reports the updated list", async () => {
    const lot = makeLot();
    const updated = { ...lot, quantity: 12 };
    mockedApi.patch.mockResolvedValue(updated);
    const onChanged = vi.fn();
    const { container } = renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[lot]} accounts={accounts} onChanged={onChanged} />,
    );

    fireEvent.click(screen.getByTitle("Edit lot"));
    const qty = screen.getByDisplayValue("10");
    fireEvent.change(qty, { target: { value: "12" } });
    fireEvent.click(commitButton(container));

    await waitFor(() => {
      expect(mockedApi.patch).toHaveBeenCalledWith("/investment_lots/l1", {
        account_id: "acc-1",
        acquired_date: "2026-01-15",
        quantity: 12,
        cost_basis: 1500,
        notes: null,
      });
    });
    await waitFor(() => expect(onChanged).toHaveBeenCalledWith([updated]));
  });

  it("validates the edit form before saving", () => {
    const { container } = renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[makeLot()]} accounts={accounts} onChanged={() => {}} />,
    );
    fireEvent.click(screen.getByTitle("Edit lot"));
    fireEvent.change(screen.getByDisplayValue("10"), { target: { value: "" } });
    fireEvent.click(commitButton(container));
    expect(screen.getByText("Quantity is required.")).toBeInTheDocument();
    expect(mockedApi.patch).not.toHaveBeenCalled();
  });

  it("cancel restores the read-only row without saving", () => {
    renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[makeLot()]} accounts={accounts} onChanged={() => {}} />,
    );
    fireEvent.click(screen.getByTitle("Edit lot"));
    fireEvent.change(screen.getByDisplayValue("10"), { target: { value: "999" } });
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.getByText("10")).toBeInTheDocument(); // original quantity shown
    expect(mockedApi.patch).not.toHaveBeenCalled();
  });
});

describe("InvestmentLotsEditor — deleting a lot", () => {
  it("DELETEs the lot and reports the remaining list", async () => {
    mockedApi.delete.mockResolvedValue(undefined);
    const onChanged = vi.fn();
    renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[makeLot()]} accounts={accounts} onChanged={onChanged} />,
    );
    fireEvent.click(screen.getByTitle("Delete lot"));
    await waitFor(() => {
      expect(mockedApi.delete).toHaveBeenCalledWith("/investment_lots/l1");
    });
    await waitFor(() => expect(onChanged).toHaveBeenCalledWith([]));
  });
});

describe("InvestmentLotsEditor — generate from transactions", () => {
  const preview = [
    { account_name: "Brokerage", acquired_date: "2026-01-02", quantity: 5, cost_basis: 500, unit_cost: 100, description: "Bought 5 AAPL" },
    { account_name: "Brokerage", acquired_date: "2026-02-02", quantity: 3, cost_basis: 450, unit_cost: 150, description: "Bought 3 AAPL" },
  ];
  const generated = [makeLot({ id: "g1" }), makeLot({ id: "g2" })];

  it("previews lots then commits with replace=false when none exist", async () => {
    mockedApi.post.mockImplementation((path: string, body?: unknown) => {
      const b = body as Record<string, unknown> | undefined;
      if (path === "/investment_lots/generate" && b?.commit) return Promise.resolve(generated as never);
      return Promise.resolve(preview as never);
    });
    const onChanged = vi.fn();
    renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={onChanged} />,
    );

    fireEvent.click(screen.getByRole("button", { name: /Generate from transactions/ }));
    expect(mockedApi.post).toHaveBeenCalledWith("/investment_lots/generate", { security_id: "sec-1" });

    expect(await screen.findByText("Bought 5 AAPL")).toBeInTheDocument();
    expect(screen.getByText(/FIFO applied/)).toBeInTheDocument();
    // Totals row inside the modal
    expect(screen.getByText("Total (2 lots)")).toBeInTheDocument();
    expect(screen.getByText("$950.00")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /Generate 2 lots/ }));
    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith("/investment_lots/generate", {
        security_id: "sec-1",
        commit: true,
        replace: false,
      });
    });
    await waitFor(() => expect(onChanged).toHaveBeenCalledWith(generated));
  });

  it("warns and uses replace=true when lots already exist", async () => {
    mockedApi.post.mockImplementation((path: string, body?: unknown) => {
      const b = body as Record<string, unknown> | undefined;
      if (path === "/investment_lots/generate" && b?.commit) return Promise.resolve(generated as never);
      return Promise.resolve(preview as never);
    });
    renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[makeLot()]} accounts={accounts} onChanged={() => {}} />,
    );

    fireEvent.click(screen.getByRole("button", { name: /Generate from transactions/ }));
    expect(await screen.findByText(/already has/)).toBeInTheDocument();
    expect(screen.getByText(/Generating will replace it/)).toBeInTheDocument();

    fireEvent.click(await screen.findByRole("button", { name: /Replace with 2 lots/ }));
    await waitFor(() => {
      expect(mockedApi.post).toHaveBeenCalledWith("/investment_lots/generate", {
        security_id: "sec-1",
        commit: true,
        replace: true,
      });
    });
  });

  it("shows an empty-preview message and disables the commit button", async () => {
    mockedApi.post.mockResolvedValue([] as never);
    renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={() => {}} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /Generate from transactions/ }));
    expect(await screen.findByText(/No purchase transactions found/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Generate 0 lots/ })).toBeDisabled();
  });

  it("closes the modal via Cancel without committing", async () => {
    mockedApi.post.mockResolvedValue(preview as never);
    renderWithClient(
      <InvestmentLotsEditor securityId="sec-1" lots={[]} accounts={accounts} onChanged={() => {}} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /Generate from transactions/ }));
    await screen.findByText("Bought 5 AAPL");
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.queryByText("Generate lots from transactions")).toBeNull();
    expect(mockedApi.post).toHaveBeenCalledTimes(1); // only the preview call
  });
});
