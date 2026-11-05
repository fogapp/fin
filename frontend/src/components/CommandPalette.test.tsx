import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor, render } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useLocation, MemoryRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderWithRouter } from "@/test/queryClient";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { CommandPalette } from "./CommandPalette";
import type { SearchResults } from "@/api/types";

const apiMock = vi.mocked(api);

const EMPTY: SearchResults = {
  merchants: [], categories: [], tags: [], accounts: [], transactions: [],
  loans: [], investment_transactions: [], securities: [],
};

const RESULTS: SearchResults = {
  ...EMPTY,
  merchants: [
    { id: "m1", name: "Whole Foods", category_name: "Groceries" },
    { id: "m2", name: "Wholesale Club", category_name: null },
  ],
  transactions: [
    { id: "t1", description: "WHOLEFDS MKT", amount: -42.5, transaction_date: "2026-07-01", merchant_name: "Whole Foods", category_name: "Groceries" },
  ],
};

function LocationDisplay() {
  const location = useLocation();
  return <div data-testid="location">{location.pathname}{location.hash}</div>;
}

function renderPalette(onOpenChange = vi.fn()) {
  const result = renderWithRouter(
    <>
      <CommandPalette open onOpenChange={onOpenChange} />
      <LocationDisplay />
    </>,
  );
  return { ...result, onOpenChange };
}

beforeEach(() => {
  vi.clearAllMocks();
  apiMock.get.mockResolvedValue(EMPTY as never);
});

describe("CommandPalette", () => {
  it("shows a hint and makes no request before anything is typed", () => {
    renderPalette();
    expect(screen.getByText(/Search merchants, categories, tags/)).toBeInTheDocument();
    expect(apiMock.get).not.toHaveBeenCalled();
  });

  it("debounces input and fetches grouped results, skipping empty groups", async () => {
    apiMock.get.mockResolvedValue(RESULTS as never);
    renderPalette();

    await userEvent.type(screen.getByRole("textbox", { name: "Search" }), "whole");

    await waitFor(() => {
      expect(apiMock.get).toHaveBeenCalledWith("/search?q=whole", expect.anything());
    });

    expect(await screen.findByText("Merchants")).toBeInTheDocument();
    expect(screen.getByText("Whole Foods")).toBeInTheDocument();
    expect(screen.getByText("Wholesale Club")).toBeInTheDocument();
    expect(screen.getByText("Transactions")).toBeInTheDocument();
    expect(screen.getByText("WHOLEFDS MKT")).toBeInTheDocument();
    // Groups with no matches (categories, tags, accounts, ...) don't render.
    expect(screen.queryByText("Categories")).not.toBeInTheDocument();
    expect(screen.queryByText("Tags")).not.toBeInTheDocument();
  });

  it("shows a no-results message once the fetch settles empty", async () => {
    renderPalette();
    await userEvent.type(screen.getByRole("textbox", { name: "Search" }), "zzz");
    expect(await screen.findByText(/No results for/)).toBeInTheDocument();
  });

  it("navigates to a merchant on click and closes the palette", async () => {
    apiMock.get.mockResolvedValue(RESULTS as never);
    const { onOpenChange } = renderPalette();

    await userEvent.type(screen.getByRole("textbox", { name: "Search" }), "whole");
    await userEvent.click(await screen.findByText("Whole Foods"));

    expect(screen.getByTestId("location")).toHaveTextContent("/merchants#id=m1");
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it("navigates the highlighted row with ArrowDown + Enter", async () => {
    apiMock.get.mockResolvedValue(RESULTS as never);
    renderPalette();

    const input = screen.getByRole("textbox", { name: "Search" });
    await userEvent.type(input, "whole");
    await screen.findByText("Whole Foods");

    // Row 0 (Whole Foods) is highlighted by default; move to row 1 (Wholesale Club).
    await userEvent.keyboard("{ArrowDown}");
    await userEvent.keyboard("{Enter}");

    expect(screen.getByTestId("location")).toHaveTextContent("/merchants#id=m2");
  });

  it("navigates a transaction result to its detail route", async () => {
    apiMock.get.mockResolvedValue(RESULTS as never);
    renderPalette();

    await userEvent.type(screen.getByRole("textbox", { name: "Search" }), "whole");
    await userEvent.click(await screen.findByText("WHOLEFDS MKT"));

    expect(screen.getByTestId("location")).toHaveTextContent("/transactions/t1");
  });

  it("clears the query when reopened after closing", async () => {
    apiMock.get.mockResolvedValue(RESULTS as never);
    const onOpenChange = vi.fn();
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const tree = (open: boolean) => (
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <CommandPalette open={open} onOpenChange={onOpenChange} />
        </MemoryRouter>
      </QueryClientProvider>
    );
    // rerender() replaces the whole tree at the root, so every call must
    // re-supply the providers — passing the bare component would lose
    // Router/QueryClient context on the second call.
    const { rerender } = render(tree(true));

    await userEvent.type(screen.getByRole("textbox", { name: "Search" }), "whole");
    expect(screen.getByRole("textbox", { name: "Search" })).toHaveValue("whole");

    rerender(tree(false));
    rerender(tree(true));

    expect(screen.getByRole("textbox", { name: "Search" })).toHaveValue("");
  });
});
