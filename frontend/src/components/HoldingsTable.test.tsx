import { describe, it, expect, vi } from "vitest";
import { screen, fireEvent, within } from "@testing-library/react";
import { useLocation } from "react-router-dom";
import { renderWithRouter } from "@/test/queryClient";
import { HoldingsTable, type HoldingRow } from "./HoldingsTable";

let seq = 0;
function makeHolding(overrides: Partial<HoldingRow> = {}): HoldingRow {
  seq += 1;
  return {
    id: `h-${seq}`,
    security_id: `sec-${seq}`,
    ticker: "AAPL",
    name: "Apple Inc.",
    cusip: "037833100",
    label: null,
    quantity: 10,
    price: 150,
    market_value: 1500,
    cost_basis: 1000,
    unrealized_gl: 500,
    unrealized_gl_pct: 50,
    asset_class: "Equity",
    est_annual_income: 12,
    dividend_yield: 0.8,
    as_of_date: "2026-06-30",
    ...overrides,
  };
}

/** Body rows of the holdings table, as trimmed text. */
function bodyRowTexts(container: HTMLElement): string[] {
  return Array.from(container.querySelectorAll("tbody tr")).map((r) => r.textContent ?? "");
}

/** The icon-only options (sliders) button. */
function optionsButton(): HTMLElement {
  return screen.getByRole("button", { name: "Table options" });
}

function LocationProbe() {
  const loc = useLocation();
  return <div data-testid="loc">{loc.pathname}</div>;
}

describe("HoldingsTable — rendering", () => {
  it("renders ticker, name, quantity, values, and G/L cells", () => {
    renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({
            ticker: "AAPL", name: "Apple Inc.", quantity: 10.5, price: 150,
            market_value: 1575, cost_basis: 1000, unrealized_gl: 575, unrealized_gl_pct: 57.5,
          }),
        ]}
      />,
    );
    expect(screen.getByText("AAPL")).toBeInTheDocument();
    expect(screen.getByText("Apple Inc.")).toBeInTheDocument();
    expect(screen.getByText("10.5")).toBeInTheDocument();
    expect(screen.getByText("$150.00")).toBeInTheDocument();
    expect(screen.getByText("$1,575.00")).toBeInTheDocument();
    expect(screen.getByText("$1,000.00")).toBeInTheDocument();
    expect(screen.getByText("+$575.00")).toBeInTheDocument();
    expect(screen.getByText("+57.50%")).toBeInTheDocument();
  });

  it("colors gains green and losses red", () => {
    renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({ ticker: "UP", unrealized_gl: 500, unrealized_gl_pct: 50 }),
          makeHolding({ ticker: "DOWN", market_value: 800, unrealized_gl: -200, unrealized_gl_pct: -20 }),
        ]}
      />,
    );
    expect(screen.getByText("+$500.00").className).toContain("text-positive");
    expect(screen.getByText("-$200.00").className).toContain("text-negative");
    expect(screen.getByText("-20.00%").className).toContain("text-negative");
  });

  it("treats a zero G/L as a (green) gain with a plus sign", () => {
    renderWithRouter(
      <HoldingsTable holdings={[makeHolding({ unrealized_gl: 0, unrealized_gl_pct: 0 })]} />,
    );
    expect(screen.getByText("+$0.00").className).toContain("text-positive");
  });

  it("renders em-dashes for a missing ticker and cost basis", () => {
    const { container } = renderWithRouter(
      <HoldingsTable holdings={[makeHolding({ ticker: null, name: null, cost_basis: null })]} />,
    );
    const row = container.querySelector("tbody tr")!;
    expect(within(row as HTMLElement).getAllByText("—").length).toBeGreaterThanOrEqual(2);
  });

  it("shows the empty state when there are no holdings", () => {
    renderWithRouter(<HoldingsTable holdings={[]} />);
    expect(screen.getByText("No holdings found.")).toBeInTheDocument();
  });

  it("renders skeleton rows and no footer while loading", () => {
    const { container } = renderWithRouter(<HoldingsTable holdings={[]} isLoading />);
    expect(container.querySelectorAll("tbody tr.animate-pulse")).toHaveLength(6);
    expect(screen.queryByText("No holdings found.")).toBeNull();
    expect(screen.queryByText(/position/)).toBeNull();
  });

  it("shows a positions count footer, singular vs plural", () => {
    const { unmount } = renderWithRouter(<HoldingsTable holdings={[makeHolding()]} />);
    expect(screen.getByText(/1 position$/)).toBeInTheDocument();
    unmount();
    renderWithRouter(<HoldingsTable holdings={[makeHolding(), makeHolding({ ticker: "MSFT" })]} />);
    expect(screen.getByText(/2 positions/)).toBeInTheDocument();
  });
});

describe("HoldingsTable — columns prop", () => {
  it("renders only the requested columns", () => {
    renderWithRouter(
      <HoldingsTable
        holdings={[makeHolding()]}
        columns={["ticker", "dividend_yield", "est_annual_income", "asset_class"]}
      />,
    );
    expect(screen.getByRole("columnheader", { name: "Ticker" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Yield" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Est. Annual Income" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Asset Class" })).toBeInTheDocument();
    expect(screen.queryByRole("columnheader", { name: "Market Value" })).toBeNull();
    // Cell formatting for the optional columns
    expect(screen.getByText("0.80%")).toBeInTheDocument();
    expect(screen.getByText("$12.00")).toBeInTheDocument();
    expect(screen.getByText("Equity")).toBeInTheDocument();
  });

  it("renders em-dashes for null yield/income/asset class", () => {
    const { container } = renderWithRouter(
      <HoldingsTable
        holdings={[makeHolding({ est_annual_income: null, dividend_yield: null, asset_class: null })]}
        columns={["ticker", "dividend_yield", "est_annual_income", "asset_class"]}
      />,
    );
    const row = container.querySelector("tbody tr")!;
    expect(within(row as HTMLElement).getAllByText("—")).toHaveLength(3);
  });
});

describe("HoldingsTable — sorting", () => {
  const holdings = [
    makeHolding({ ticker: "AAPL", market_value: 1500 }),
    makeHolding({ ticker: "ZM", market_value: 3000 }),
    makeHolding({ ticker: "MSFT", market_value: 2000 }),
  ];

  it("sorts by market value descending by default", () => {
    const { container } = renderWithRouter(<HoldingsTable holdings={holdings} />);
    const rows = bodyRowTexts(container);
    expect(rows[0]).toContain("ZM");
    expect(rows[1]).toContain("MSFT");
    expect(rows[2]).toContain("AAPL");
  });

  it("clicking a header sorts by that column desc, then toggles asc", () => {
    const { container } = renderWithRouter(<HoldingsTable holdings={holdings} />);
    fireEvent.click(screen.getByRole("columnheader", { name: "Ticker" }));
    expect(bodyRowTexts(container)[0]).toContain("ZM"); // desc: Z first
    fireEvent.click(screen.getByRole("columnheader", { name: "Ticker" }));
    expect(bodyRowTexts(container)[0]).toContain("AAPL"); // asc: A first
  });
});

describe("HoldingsTable — search", () => {
  it("filters by ticker or name and shows the filtered footer count", () => {
    const { container } = renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({ ticker: "AAPL", name: "Apple Inc." }),
          makeHolding({ ticker: "MSFT", name: "Microsoft Corp." }),
        ]}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Search" }));
    fireEvent.change(screen.getByPlaceholderText("Search ticker or name…"), {
      target: { value: "micro" },
    });
    expect(bodyRowTexts(container)).toHaveLength(1);
    expect(screen.getByText("MSFT")).toBeInTheDocument();
    expect(screen.queryByText("AAPL")).toBeNull();
    expect(screen.getByText(/1 position \(2 total\)/)).toBeInTheDocument();
  });

  it("shows the no-match message when search excludes everything", () => {
    renderWithRouter(<HoldingsTable holdings={[makeHolding({ ticker: "AAPL" })]} />);
    fireEvent.click(screen.getByRole("button", { name: "Search" }));
    fireEvent.change(screen.getByPlaceholderText("Search ticker or name…"), {
      target: { value: "zzz" },
    });
    expect(screen.getByText("No holdings match the current filters.")).toBeInTheDocument();
  });
});

describe("HoldingsTable — options panel", () => {
  it("groups by asset class with per-group counts", () => {
    renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({ ticker: "AAPL", asset_class: "Equity" }),
          makeHolding({ ticker: "MSFT", asset_class: "Equity" }),
          makeHolding({ ticker: "BND", asset_class: "Bond" }),
          makeHolding({ ticker: "???", asset_class: null }),
        ]}
      />,
    );
    fireEvent.click(optionsButton());
    const groupSection = screen.getByText("Group by").parentElement!;
    fireEvent.click(within(groupSection).getByRole("button", { name: "Asset Class" }));
    expect(screen.getByText("Bond")).toBeInTheDocument();
    expect(screen.getByText("Unknown")).toBeInTheDocument();
    expect(screen.getByText("(2)")).toBeInTheDocument(); // Equity group count
  });

  it("toggles a column off (but keeps clicking a missing one additive)", () => {
    renderWithRouter(<HoldingsTable holdings={[makeHolding()]} />);
    fireEvent.click(optionsButton());
    const columnsSection = screen.getByText("Columns").parentElement!;
    fireEvent.click(within(columnsSection).getByRole("button", { name: "Cost Basis" }));
    expect(screen.queryByRole("columnheader", { name: "Cost Basis" })).toBeNull();
    fireEvent.click(within(columnsSection).getByRole("button", { name: "Yield" }));
    expect(screen.getByRole("columnheader", { name: "Yield" })).toBeInTheDocument();
  });

  it("adds a numeric filter, shows it as a chip, and filters rows", () => {
    const { container } = renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({ ticker: "BIG", market_value: 3000 }),
          makeHolding({ ticker: "SMALL", market_value: 100 }),
        ]}
      />,
    );
    fireEvent.click(optionsButton());
    fireEvent.click(screen.getByRole("button", { name: "Add filter" }));
    // Filter row defaults to Market Value > (blank value passes everything)
    expect(bodyRowTexts(container)).toHaveLength(2);
    fireEvent.change(screen.getByPlaceholderText("0"), { target: { value: "1000" } });
    expect(bodyRowTexts(container)).toHaveLength(1);
    expect(screen.getByText("BIG")).toBeInTheDocument();
    // Chip in the toolbar
    expect(screen.getByText(/Market Value > 1000/)).toBeInTheDocument();
  });

  it("hides the value input for blank/present operators and applies them", () => {
    const { container } = renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({ ticker: "ZERO", unrealized_gl: 0 }),
          makeHolding({ ticker: "GAIN", unrealized_gl: 100 }),
        ]}
      />,
    );
    fireEvent.click(optionsButton());
    fireEvent.click(screen.getByRole("button", { name: "Add filter" }));

    const panel = screen.getByText("Filters").parentElement!;
    const [fieldSelect, operatorSelect] = Array.from(panel.querySelectorAll("select"));
    fireEvent.change(fieldSelect, { target: { value: "unrealized_gl" } });
    fireEvent.change(operatorSelect, { target: { value: "blank" } });

    expect(screen.queryByPlaceholderText("0")).toBeNull(); // value input hidden
    expect(bodyRowTexts(container)).toHaveLength(1);
    expect(screen.getByText("ZERO")).toBeInTheDocument();

    fireEvent.change(operatorSelect, { target: { value: "present" } });
    expect(bodyRowTexts(container)).toHaveLength(1);
    expect(screen.getByText("GAIN")).toBeInTheDocument();
  });

  it("filters by asset class equality (case-insensitive)", () => {
    const { container } = renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({ ticker: "AAPL", asset_class: "Equity" }),
          makeHolding({ ticker: "BND", asset_class: "Bond" }),
        ]}
      />,
    );
    fireEvent.click(optionsButton());
    fireEvent.click(screen.getByRole("button", { name: "Add filter" }));

    const panel = screen.getByText("Filters").parentElement!;
    const [fieldSelect, operatorSelect] = Array.from(panel.querySelectorAll("select"));
    fireEvent.change(fieldSelect, { target: { value: "asset_class" } });
    fireEvent.change(operatorSelect, { target: { value: "equals" } });
    fireEvent.change(screen.getByPlaceholderText("value"), { target: { value: "bond" } });

    expect(bodyRowTexts(container)).toHaveLength(1);
    expect(screen.getByText("BND")).toBeInTheDocument();
  });

  it("removes a filter via its toolbar chip", () => {
    const { container } = renderWithRouter(
      <HoldingsTable holdings={[makeHolding({ market_value: 100 })]} />,
    );
    fireEvent.click(optionsButton());
    fireEvent.click(screen.getByRole("button", { name: "Add filter" }));
    fireEvent.change(screen.getByPlaceholderText("0"), { target: { value: "1000" } });
    expect(screen.getByText("No holdings match the current filters.")).toBeInTheDocument();

    const chip = screen.getByText(/Market Value > 1000/);
    fireEvent.click(within(chip as HTMLElement).getByRole("button"));
    expect(bodyRowTexts(container)).toHaveLength(1);
  });
});

describe("HoldingsTable — refresh & navigation", () => {
  it("calls onRefresh when the refresh button is clicked", () => {
    const onRefresh = vi.fn();
    renderWithRouter(<HoldingsTable holdings={[makeHolding()]} onRefresh={onRefresh} />);
    fireEvent.click(screen.getByTitle("Refresh holdings"));
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it("disables the refresh button while refreshing", () => {
    renderWithRouter(
      <HoldingsTable holdings={[makeHolding()]} onRefresh={() => {}} isRefreshing />,
    );
    expect(screen.getByTitle("Refresh holdings")).toBeDisabled();
  });

  it("navigates to the market page when a ticker is clicked", () => {
    renderWithRouter(
      <>
        <HoldingsTable holdings={[makeHolding({ ticker: "AAPL" })]} />
        <LocationProbe />
      </>,
    );
    fireEvent.click(screen.getByRole("button", { name: /AAPL/ }));
    expect(screen.getByTestId("loc")).toHaveTextContent("/market/AAPL");
  });
});

describe("HoldingsTable — labels", () => {
  it("prefers the label, then the ticker, then the description", () => {
    const { container } = renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({ label: "Emergency fund", ticker: "VMFXX", name: "Vanguard Federal MMF", market_value: 3000 }),
          makeHolding({ label: null, ticker: "AAPL", name: "Apple Inc.", market_value: 2000 }),
          makeHolding({ label: null, ticker: null, name: "Untradeable Trust Unit", market_value: 1000 }),
        ]}
      />,
    );
    const rows = bodyRowTexts(container);
    expect(rows[0]).toContain("Emergency fund");
    expect(rows[0]).toContain("VMFXX"); // ticker demoted to the subtitle
    expect(rows[1]).toContain("AAPL");
    expect(rows[2]).toContain("Untradeable Trust Unit");
  });

  it("matches a search against the label", () => {
    const { container } = renderWithRouter(
      <HoldingsTable
        holdings={[
          makeHolding({ label: "Emergency fund", ticker: "VMFXX", name: "Vanguard Federal MMF" }),
          makeHolding({ ticker: "AAPL", name: "Apple Inc." }),
        ]}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Search" }));
    fireEvent.change(screen.getByPlaceholderText("Search ticker or name…"), {
      target: { value: "emergency" },
    });
    expect(bodyRowTexts(container)).toHaveLength(1);
    expect(screen.getByText("Emergency fund")).toBeInTheDocument();
  });
});

describe("HoldingsTable — detail drawer", () => {
  it("opens on row click showing CUSIP, description, and the label field", () => {
    const { container } = renderWithRouter(
      <HoldingsTable holdings={[makeHolding({ ticker: "AAPL", name: "Apple Inc.", cusip: "037833100" })]} />,
    );
    expect(screen.queryByLabelText("Label")).toBeNull();

    fireEvent.click(container.querySelector("tbody tr")!);

    expect(screen.getByText("Holding")).toBeInTheDocument();
    expect(screen.getByText("037833100")).toBeInTheDocument();
    expect(screen.getByLabelText("Label")).toHaveValue("");
    // Description appears both in the row subtitle and in the drawer
    expect(screen.getAllByText("Apple Inc.").length).toBeGreaterThan(1);
  });

  it("prefills the label field and closes on the close button", () => {
    const { container } = renderWithRouter(
      <HoldingsTable holdings={[makeHolding({ label: "Emergency fund" })]} />,
    );
    fireEvent.click(container.querySelector("tbody tr")!);
    expect(screen.getByLabelText("Label")).toHaveValue("Emergency fund");

    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(screen.queryByLabelText("Label")).toBeNull();
  });
});
