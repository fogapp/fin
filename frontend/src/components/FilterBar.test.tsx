import { describe, it, expect, vi, beforeAll, afterAll } from "vitest";
import { screen, fireEvent, within } from "@testing-library/react";
import type { ComponentProps } from "react";
import { renderWithClient } from "@/test/queryClient";

vi.mock("@/api/client", () => ({
  api: {
    get: vi.fn((path: string) => {
      if (path === "/merchants") {
        return Promise.resolve([{ id: "m1", name: "Starbucks", transaction_count: 3 }]);
      }
      if (path === "/categories") {
        return Promise.resolve([
          { id: "c1", name: "Food", parent_id: null, transaction_count: 0 },
          { id: "c2", name: "Coffee shops", parent_id: "c1", transaction_count: 0 },
        ]);
      }
      return Promise.resolve([]);
    }),
    post: vi.fn(() => Promise.resolve({})),
    patch: vi.fn(() => Promise.resolve({})),
    delete: vi.fn(() => Promise.resolve(undefined)),
  },
}));

import {
  FilterBar,
  DisplayOptionsPanel,
  CASH_FIELDS,
  ALL_COLUMNS,
  type ActiveFilter,
  type ColumnKey,
} from "./FilterBar";
import type { SavedView } from "@/api/types";

// jsdom reports zero-size rects, which makes FilterBar's popovers/submenus
// compute off-screen (or hidden) positions. Give every element a plausible box.
beforeAll(() => {
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue({
    top: 10, left: 10, right: 200, bottom: 30, width: 190, height: 20,
    x: 10, y: 10, toJSON: () => ({}),
  } as DOMRect);
});
afterAll(() => {
  (Element.prototype.getBoundingClientRect as unknown as { mockRestore: () => void }).mockRestore();
});

describe("FilterBar — exports", () => {
  it("CASH_FIELDS has all the expected default fields", () => {
    const keys = CASH_FIELDS.map((f) => f.key);
    expect(keys).toEqual(expect.arrayContaining([
      "transaction_date", "description", "amount",
    ]));
  });

  it("ALL_COLUMNS lists the eight standard columns", () => {
    expect(ALL_COLUMNS).toEqual([
      "date", "description", "merchant", "category", "account", "amount", "type", "tags", "note",
    ]);
  });
});

describe("FilterBar — render", () => {
  it("renders empty state with no filters", () => {
    renderWithClient(
      <FilterBar
        filters={[]}
        matchAll
        onChange={() => {}}
        onMatchAllChange={() => {}}
      />,
    );
    // Empty filterbar: no pills, no + button (per source: hasFilters guard)
    expect(screen.queryByTitle("Add filter")).toBeNull();
  });

  it("renders a pill per active filter", () => {
    const filters: ActiveFilter[] = [
      { _key: 1, field: "description", operator: "contains", value: "STARBUCKS" },
      { _key: 2, field: "amount", operator: "greater_than", value: "10" },
    ];
    renderWithClient(
      <FilterBar
        filters={filters}
        matchAll
        onChange={() => {}}
        onMatchAllChange={() => {}}
      />,
    );
    expect(screen.getByText(/STARBUCKS/)).toBeInTheDocument();
    expect(screen.getByText(/10/)).toBeInTheDocument();
    // The + button only appears once at least one filter exists
    expect(screen.getByTitle("Add filter")).toBeInTheDocument();
  });

  it("shows match ALL/ANY toggle when more than one filter is active", () => {
    const filters: ActiveFilter[] = [
      { _key: 1, field: "description", operator: "contains", value: "a" },
      { _key: 2, field: "description", operator: "contains", value: "b" },
    ];
    renderWithClient(
      <FilterBar
        filters={filters}
        matchAll
        onChange={() => {}}
        onMatchAllChange={() => {}}
      />,
    );
    expect(screen.getByText(/match/)).toBeInTheDocument();
    // ALL/ANY toggle
    expect(screen.getByRole("button", { name: /all|any/i })).toBeInTheDocument();
  });

  it("toggles match-all when ALL/ANY button is clicked", () => {
    const onMatchAllChange = vi.fn();
    renderWithClient(
      <FilterBar
        filters={[
          { _key: 1, field: "description", operator: "contains", value: "a" },
          { _key: 2, field: "description", operator: "contains", value: "b" },
        ]}
        matchAll
        onChange={() => {}}
        onMatchAllChange={onMatchAllChange}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /all|any/i }));
    expect(onMatchAllChange).toHaveBeenCalledWith(false);
  });
});

// ── Adding filters through the field picker ──────────────────────────────────

function renderBar(overrides: Partial<ComponentProps<typeof FilterBar>> = {}) {
  const onChange = vi.fn();
  const utils = renderWithClient(
    <FilterBar
      filters={[]}
      matchAll
      onChange={onChange}
      onMatchAllChange={() => {}}
      {...overrides}
    />,
  );
  return { onChange, ...utils };
}

function openPickerAndHover(fieldLabel: string) {
  fireEvent.click(screen.getByTitle("Filter"));
  fireEvent.mouseEnter(screen.getByRole("button", { name: fieldLabel }));
}

describe("FilterBar — adding filters", () => {
  it("commits a text filter (description contains) via Apply", () => {
    const { onChange } = renderBar();
    openPickerAndHover("Description");
    fireEvent.change(screen.getByPlaceholderText("Enter text…"), { target: { value: "COFFEE" } });
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange.mock.calls[0][0]).toEqual([
      expect.objectContaining({ field: "description", operator: "contains", value: "COFFEE" }),
    ]);
    // Picker closes after commit
    expect(screen.queryByPlaceholderText("Enter text…")).toBeNull();
  });

  it("disables Apply while the text value is empty", () => {
    renderBar();
    openPickerAndHover("Description");
    expect(screen.getByRole("button", { name: "Apply" })).toBeDisabled();
  });

  it("commits an amount filter with a chosen operator via Enter", () => {
    const { onChange } = renderBar();
    openPickerAndHover("Amount");
    fireEvent.click(screen.getByRole("tab", { name: "<" }));
    const input = screen.getByPlaceholderText("Amount…");
    fireEvent.change(input, { target: { value: "50" } });
    fireEvent.keyDown(input, { key: "Enter" });
    expect(onChange.mock.calls[0][0]).toEqual([
      expect.objectContaining({ field: "amount", operator: "less_than", value: "50" }),
    ]);
  });

  it("commits a select filter (source) by clicking an option", () => {
    const { onChange } = renderBar();
    openPickerAndHover("Source");
    fireEvent.click(screen.getByRole("button", { name: "Bank" }));
    expect(onChange.mock.calls[0][0]).toEqual([
      expect.objectContaining({ field: "source", operator: "equals", value: "bank" }),
    ]);
  });

  it("commits a blank-operator merchant filter via 'No merchant'", () => {
    const { onChange } = renderBar();
    openPickerAndHover("Merchant");
    fireEvent.click(screen.getByRole("button", { name: "No merchant" }));
    expect(onChange.mock.calls[0][0]).toEqual([
      expect.objectContaining({ field: "merchant_id", operator: "blank", value: "" }),
    ]);
  });

  it("lists only root categories and commits category equals", async () => {
    const { onChange } = renderBar();
    openPickerAndHover("Category");
    const food = await screen.findByRole("button", { name: "Food" });
    expect(screen.queryByRole("button", { name: "Coffee shops" })).toBeNull();
    fireEvent.click(food);
    expect(onChange.mock.calls[0][0]).toEqual([
      expect.objectContaining({ field: "category_id", operator: "equals", value: "c1" }),
    ]);
  });

  it("commits a month date filter by default", () => {
    const { container, onChange } = renderBar();
    openPickerAndHover("Date");
    const monthInput = container.ownerDocument.querySelector('input[type="month"]')!;
    fireEvent.change(monthInput, { target: { value: "2026-03" } });
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));
    expect(onChange.mock.calls[0][0]).toEqual([
      expect.objectContaining({ field: "transaction_date", operator: "month", value: "2026-03" }),
    ]);
  });

  it("switches the date filter to on-or-after (gte)", () => {
    const { container, onChange } = renderBar();
    openPickerAndHover("Date");
    fireEvent.click(screen.getByRole("tab", { name: "After" }));
    const dateInput = container.ownerDocument.querySelector('input[type="date"]')!;
    fireEvent.change(dateInput, { target: { value: "2026-03-15" } });
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));
    expect(onChange.mock.calls[0][0]).toEqual([
      expect.objectContaining({ field: "transaction_date", operator: "gte", value: "2026-03-15" }),
    ]);
  });

  it("appends via the + button when filters already exist", () => {
    const existing: ActiveFilter[] = [
      { _key: 1, field: "description", operator: "contains", value: "a" },
    ];
    const { onChange } = renderBar({ filters: existing });
    fireEvent.click(screen.getByTitle("Add filter"));
    fireEvent.mouseEnter(screen.getByRole("button", { name: "Amount" }));
    const input = screen.getByPlaceholderText("Amount…");
    fireEvent.change(input, { target: { value: "5" } });
    fireEvent.keyDown(input, { key: "Enter" });
    const next = onChange.mock.calls[0][0];
    expect(next).toHaveLength(2);
    expect(next[0]).toEqual(existing[0]);
    expect(next[1]).toEqual(
      expect.objectContaining({ field: "amount", operator: "greater_than", value: "5" }),
    );
  });

  it("closes the picker on Escape without committing", () => {
    const { onChange } = renderBar();
    fireEvent.click(screen.getByTitle("Filter"));
    expect(screen.getByRole("button", { name: "Description" })).toBeInTheDocument();
    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByRole("button", { name: "Description" })).toBeNull();
    expect(onChange).not.toHaveBeenCalled();
  });

  it("closes the picker when the backdrop is clicked", () => {
    renderBar();
    fireEvent.click(screen.getByTitle("Filter"));
    const backdrop = document.querySelector(".fixed.inset-0.z-40")!;
    fireEvent.click(backdrop);
    expect(screen.queryByRole("button", { name: "Description" })).toBeNull();
  });
});

// ── Pills ─────────────────────────────────────────────────────────────────────

describe("FilterBar — pills", () => {
  it("shows an 'empty' badge for blank-operator filters", () => {
    renderBar({
      filters: [{ _key: 1, field: "merchant_id", operator: "blank", value: "" }],
    });
    expect(screen.getByText("Merchant")).toBeInTheDocument();
    expect(screen.getByText("is empty")).toBeInTheDocument();
    expect(screen.getByText("empty")).toBeInTheDocument();
  });

  it("displays the select option label instead of the raw value", () => {
    renderBar({
      filters: [{ _key: 1, field: "source", operator: "equals", value: "bank" }],
    });
    expect(screen.getByText("Bank")).toBeInTheDocument();
    expect(screen.queryByText("bank")).toBeNull();
  });

  it("resolves a merchant id to its name from the merchants query", async () => {
    renderBar({
      filters: [{ _key: 1, field: "merchant_id", operator: "equals", value: "m1" }],
    });
    expect(await screen.findByText("Starbucks")).toBeInTheDocument();
  });

  it("opens the value editor when the pill is clicked and patches the value", () => {
    const filters: ActiveFilter[] = [
      { _key: 7, field: "description", operator: "contains", value: "old" },
    ];
    const { onChange } = renderBar({ filters });
    fireEvent.click(screen.getByRole("button", { name: /Description\s*contains\s*old/ }));
    const input = screen.getByDisplayValue("old");
    fireEvent.change(input, { target: { value: "new" } });
    expect(onChange).toHaveBeenCalledWith([
      { _key: 7, field: "description", operator: "contains", value: "new" },
    ]);
  });

  it("patches the operator from the amount value editor", () => {
    const filters: ActiveFilter[] = [
      { _key: 3, field: "amount", operator: "greater_than", value: "10" },
    ];
    const { onChange } = renderBar({ filters });
    fireEvent.click(screen.getByRole("button", { name: /Amount\s*>\s*10/ }));
    fireEvent.click(screen.getByRole("tab", { name: "=" }));
    expect(onChange).toHaveBeenCalledWith([
      { _key: 3, field: "amount", operator: "equals", value: "10" },
    ]);
  });

  it("removes a single filter via the pill's ✕ button", () => {
    const filters: ActiveFilter[] = [
      { _key: 1, field: "description", operator: "contains", value: "keep" },
      { _key: 2, field: "description", operator: "contains", value: "drop" },
    ];
    const { onChange } = renderBar({ filters });
    const pill = screen.getByText("drop").closest("div")!;
    const removeBtn = within(pill as HTMLElement).getAllByRole("button").at(-1)!;
    fireEvent.click(removeBtn);
    expect(onChange).toHaveBeenCalledWith([filters[0]]);
  });

  it("clears everything via Clear Filters", () => {
    const { onChange } = renderBar({
      filters: [{ _key: 1, field: "description", operator: "contains", value: "x" }],
    });
    fireEvent.click(screen.getByRole("button", { name: "Clear filters" }));
    expect(onChange).toHaveBeenCalledWith([]);
  });
});

// ── Result count, search, save, views ─────────────────────────────────────────

describe("FilterBar — count, search, and views", () => {
  it("renders a pluralized result count", () => {
    const { unmount } = renderBar({ resultCount: 5 });
    expect(screen.getByText("5 results")).toBeInTheDocument();
    unmount();
    renderBar({ resultCount: 1 });
    expect(screen.getByText("1 result")).toBeInTheDocument();
  });

  it("hides the result count while loading", () => {
    renderBar({ resultCount: 5, isLoading: true });
    expect(screen.queryByText("5 results")).toBeNull();
  });

  it("opens the search input, forwards typing, and clears on Escape", () => {
    const onSearchChange = vi.fn();
    renderBar({ searchQuery: "", onSearchChange });
    fireEvent.click(screen.getByTitle("Search"));
    const input = screen.getByPlaceholderText("Search…");
    fireEvent.change(input, { target: { value: "latte" } });
    expect(onSearchChange).toHaveBeenCalledWith("latte");
    fireEvent.keyDown(input, { key: "Escape" });
    expect(onSearchChange).toHaveBeenCalledWith("");
  });

  it("shows Save only when there are filters and onSave is given", () => {
    const onSave = vi.fn();
    const { unmount } = renderBar({ onSave });
    expect(screen.queryByRole("button", { name: "Save" })).toBeNull();
    unmount();
    renderBar({
      onSave,
      filters: [{ _key: 1, field: "description", operator: "contains", value: "x" }],
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(onSave).toHaveBeenCalledTimes(1);
  });

  it("lists saved views and applies one on click", () => {
    const onApplyView = vi.fn();
    const views: SavedView[] = [
      { id: "v1", name: "Groceries", conditions: [], match_all: true, created_at: "2026-01-01" },
      { id: "v2", name: "Travel", conditions: [], match_all: false, created_at: "2026-01-01" },
    ];
    renderBar({ savedViews: views, onApplyView, activeViewId: "v2" });
    fireEvent.click(screen.getByTitle("Saved views"));
    fireEvent.click(screen.getByRole("button", { name: "Groceries" }));
    expect(onApplyView).toHaveBeenCalledWith(views[0]);
    // popover closed after applying
    expect(screen.queryByRole("button", { name: "Travel" })).toBeNull();
  });
});

// ── Display options ───────────────────────────────────────────────────────────

describe("FilterBar — display options", () => {
  const displayProps = {
    columns: [...ALL_COLUMNS] as ColumnKey[],
    groupBy: "none",
    primarySort: { field: "date", dir: "desc" } as const,
  };

  it("toggles a column off through the popover panel", () => {
    const onColumnsChange = vi.fn();
    renderBar({ display: { ...displayProps, onColumnsChange } });
    fireEvent.click(screen.getByTitle("Display options"));
    fireEvent.click(screen.getByRole("button", { name: "Merchant" }));
    expect(onColumnsChange).toHaveBeenCalledWith(
      ALL_COLUMNS.filter((c) => c !== "merchant"),
    );
  });

  it("changes grouping via the group-by chips", () => {
    const onGroupByChange = vi.fn();
    renderBar({ display: { ...displayProps, onGroupByChange } });
    fireEvent.click(screen.getByTitle("Display options"));
    fireEvent.click(screen.getByRole("tab", { name: "Month" }));
    expect(onGroupByChange).toHaveBeenCalledWith("month");
  });
});

describe("DisplayOptionsPanel", () => {
  it("never removes the last remaining column", () => {
    const onColumnsChange = vi.fn();
    renderWithClient(
      <DisplayOptionsPanel columns={["date"]} onColumnsChange={onColumnsChange} groupBy="none" />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Date" }));
    expect(onColumnsChange).not.toHaveBeenCalled();
  });

  it("adds a column back when it is toggled on", () => {
    const onColumnsChange = vi.fn();
    renderWithClient(
      <DisplayOptionsPanel columns={["date"]} onColumnsChange={onColumnsChange} groupBy="none" />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Amount" }));
    expect(onColumnsChange).toHaveBeenCalledWith(["date", "amount"]);
  });

  it("updates the primary sort field and toggles its direction", () => {
    const onPrimarySort = vi.fn();
    renderWithClient(
      <DisplayOptionsPanel
        columns={["date"]}
        groupBy="none"
        primarySort={{ field: "date", dir: "desc" }}
        onPrimarySort={onPrimarySort}
      />,
    );
    const [primarySelect] = screen.getAllByRole("combobox");
    fireEvent.change(primarySelect, { target: { value: "amount" } });
    expect(onPrimarySort).toHaveBeenCalledWith({ field: "amount", dir: "desc" });

    fireEvent.click(screen.getByTitle("Descending"));
    expect(onPrimarySort).toHaveBeenCalledWith({ field: "date", dir: "asc" });
  });

  it("sets, and clears, the secondary sort", () => {
    const onSecondarySort = vi.fn();
    const { unmount } = renderWithClient(
      <DisplayOptionsPanel
        columns={["date"]}
        groupBy="none"
        primarySort={{ field: "date", dir: "desc" }}
        onPrimarySort={() => {}}
        secondarySort={null}
        onSecondarySort={onSecondarySort}
      />,
    );
    const [, secondarySelect] = screen.getAllByRole("combobox");
    fireEvent.change(secondarySelect, { target: { value: "merchant" } });
    expect(onSecondarySort).toHaveBeenCalledWith({ field: "merchant", dir: "asc" });
    unmount();

    const onClear = vi.fn();
    renderWithClient(
      <DisplayOptionsPanel
        columns={["date"]}
        groupBy="none"
        primarySort={{ field: "date", dir: "desc" }}
        onPrimarySort={() => {}}
        secondarySort={{ field: "merchant", dir: "asc" }}
        onSecondarySort={onClear}
      />,
    );
    fireEvent.click(screen.getByTitle("Clear"));
    expect(onClear).toHaveBeenCalledWith(null);
  });

  it("toggles the show-transfers switch", () => {
    const onShowTransfersChange = vi.fn();
    renderWithClient(
      <DisplayOptionsPanel
        columns={["date"]}
        groupBy="none"
        showTransfers={false}
        onShowTransfersChange={onShowTransfersChange}
      />,
    );
    fireEvent.click(screen.getByRole("switch", { name: "Show transfers" }));
    expect(onShowTransfersChange).toHaveBeenCalledWith(true);
  });
});
