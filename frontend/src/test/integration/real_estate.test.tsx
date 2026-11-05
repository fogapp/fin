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
import { formatDate } from "@/lib/utils";
import type { RealEstateIndex, RealEstateProperty, RealEstatePropertyDetail } from "@/api/types";

const apiMock = vi.mocked(api);

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const PROPERTY: RealEstateProperty = {
  id: "p1", name: "Primary residence",
  address_line1: "5500 Grand Lake Dr", address_line2: null,
  city: "San Antonio", state: "TX", zip_code: "78244",
  formatted_address: "5500 Grand Lake Dr, San Antonio, TX 78244",
  display_address: "5500 Grand Lake Dr, San Antonio, TX 78244",
  status: "owned",
  purchase_date: "2019-06-01", purchase_price: 720000,
  sold_date: null, sold_price: null,
  value: 912000, value_source: "rentcast", value_as_of: "2026-07-20",
  value_low: 870000, value_high: 960000,
  mortgage_balance: 418300, equity: 493700, loan_to_value: 45.9,
  mortgages: [{ id: "l1", name: "Primary mortgage", lender: "Chase" }],
  sync_enabled: true, last_synced_at: "2026-07-20T06:15:00Z", last_sync_error: null,
  created_at: "2026-01-01T00:00:00Z", updated_at: "2026-07-20T06:15:00Z",
};

const DETAIL: RealEstatePropertyDetail = {
  ...PROPERTY,
  notes: null,
  facts: {
    property_type: "Single Family", bedrooms: 3, bathrooms: 2,
    square_footage: 1878, lot_size: 8850, year_built: 1973,
    hoa_fee: 175, latitude: 29.475962, longitude: -98.351442,
  },
  valuations: [
    { id: "v1", as_of: "2019-06-01", amount: 720000, source: "purchase", value_low: null, value_high: null },
    { id: "v2", as_of: "2023-12-31", amount: 600000, source: "tax_assessment", value_low: null, value_high: null },
    { id: "v3", as_of: "2024-12-31", amount: 648000, source: "tax_assessment", value_low: null, value_high: null },
    { id: "v4", as_of: "2026-07-20", amount: 912000, source: "rentcast", value_low: 870000, value_high: 960000 },
  ],
};

const CONNECTED: RealEstateIndex = {
  properties: [PROPERTY],
  totals: { value: 912000, mortgage: 418300, equity: 493700, count: 1 },
  rentcast: { configured: true, remaining_quota: 39, request_limit: 50, last_synced_at: "2026-07-20T06:15:00Z" },
};

const UNCONFIGURED: RealEstateIndex = {
  properties: [],
  totals: { value: 0, mortgage: 0, equity: 0, count: 0 },
  rentcast: { configured: false, remaining_quota: null, request_limit: 50, last_synced_at: null },
};

function mockRoutes(index: RealEstateIndex = CONNECTED, detail: RealEstatePropertyDetail = DETAIL) {
  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/real_estate_properties") return index as never;
    if (path.startsWith("/real_estate_properties/")) return detail as never;
    return [] as never;
  });
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

  mockRoutes();
});

const PATH = "/investments#section=real_estate";

describe("Real estate section", () => {
  it("shows totals, value, source and equity for each property", async () => {
    renderApp({ initialPath: PATH, initialToken: "tok" });

    expect(await screen.findByRole("heading", { name: "Real Estate" })).toBeInTheDocument();
    expect(screen.getByText("Primary residence")).toBeInTheDocument();
    expect(screen.getByText("$912,000.00")).toBeInTheDocument();
    expect(screen.getByText(/Equity \$493,700\.00/)).toBeInTheDocument();
    expect(screen.getByText(/45\.9% LTV/)).toBeInTheDocument();
  });

  it("prompts to connect RentCast when the integration is missing", async () => {
    mockRoutes(UNCONFIGURED);
    renderApp({ initialPath: PATH, initialToken: "tok" });

    expect(await screen.findByText("Value properties automatically")).toBeInTheDocument();
    expect(screen.getByText("No properties yet.")).toBeInTheDocument();
  });

  it("requires a value in the add form when RentCast isn't configured", async () => {
    mockRoutes(UNCONFIGURED);
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByRole("button", { name: /Add property/i }));
    await user.type(screen.getByLabelText(/^Name/), "Cabin");
    await user.type(screen.getByLabelText(/Street address/), "1 Main St");

    const submit = screen.getByRole("button", { name: /^Add property$/i });
    expect(submit).toBeDisabled();

    await user.type(screen.getByLabelText(/^Current value/), "300000");
    expect(submit).toBeEnabled();
  });

  it("posts a new property", async () => {
    const user = userEvent.setup();
    apiMock.post.mockResolvedValue({ ...PROPERTY, id: "p2", name: "Cabin", value: 300000 } as never);
    renderApp({ initialPath: PATH, initialToken: "tok" });

    expect(await screen.findByText("Primary residence")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /Add property/i }));
    await user.type(await screen.findByLabelText(/^Name/), "Cabin");
    await user.type(screen.getByLabelText(/Street address/), "1 Main St");
    await user.click(screen.getByRole("button", { name: /^Add property$/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith(
        "/real_estate_properties",
        expect.objectContaining({ name: "Cabin", address_line1: "1 Main St" }),
      );
    });
  });

  it("offers a visible way to add another property once one exists", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    // Not tucked into the page-actions dropdown — reachable directly.
    const add = await screen.findByRole("button", { name: /Add property/i });
    expect(add).toBeVisible();

    await user.click(add);
    expect(await screen.findByLabelText(/Street address/)).toBeInTheDocument();
    // The existing property stays listed alongside the new-property form.
    expect(screen.getByText("Primary residence")).toBeInTheDocument();
  });

  it("adds a second property alongside the first", async () => {
    const user = userEvent.setup();
    const second = { ...PROPERTY, id: "p2", name: "Lake cabin", value: 300000 };
    apiMock.post.mockResolvedValue(second as never);
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByRole("button", { name: /Add property/i }));
    await user.type(await screen.findByLabelText(/^Name/), "Lake cabin");
    await user.type(screen.getByLabelText(/Street address/), "9 Shoreline Rd");

    // Both properties come back on the refetch.
    apiMock.get.mockImplementation(async (path: string) => {
      if (path === "/me") return ME_PAYLOAD as never;
      if (path === "/preferences") return { data: {} } as never;
      if (path === "/real_estate_properties") {
        return {
          ...CONNECTED,
          properties: [ PROPERTY, second ],
          totals: { value: 1212000, mortgage: 418300, equity: 793700, count: 2 },
        } as never;
      }
      return [] as never;
    });

    await user.click(screen.getByRole("button", { name: /^Add property$/i }));

    expect(await screen.findByText("Lake cabin")).toBeInTheDocument();
    expect(screen.getByText("Primary residence")).toBeInTheDocument();
    expect(screen.getByText("2 properties")).toBeInTheDocument();
  });

  it("toggles the form closed again without adding anything", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByRole("button", { name: /Add property/i }));
    await user.click(screen.getByRole("button", { name: /^Cancel$/i }));

    expect(screen.queryByLabelText(/Street address/)).not.toBeInTheDocument();
    expect(apiMock.post).not.toHaveBeenCalled();
  });

  it("warns when the monthly request allowance is nearly gone", async () => {
    mockRoutes({ ...CONNECTED, rentcast: { ...CONNECTED.rentcast, remaining_quota: 2 } });
    renderApp({ initialPath: PATH, initialToken: "tok" });

    expect(await screen.findByText(/2 of 50 RentCast requests left/)).toBeInTheDocument();
  });

  it("marks a property that RentCast can't value as manual", async () => {
    mockRoutes({ ...CONNECTED, properties: [{ ...PROPERTY, sync_enabled: false, value_source: "manual" }] });
    renderApp({ initialPath: PATH, initialToken: "tok" });

    expect(await screen.findByText("Manual")).toBeInTheDocument();
  });
});

describe("Real estate property detail", () => {
  it("opens the detail view with facts, mortgage and valuation history", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByText("Primary residence"));

    expect(await screen.findByText("Value history")).toBeInTheDocument();
    expect(screen.getByText("Single Family")).toBeInTheDocument();
    expect(screen.getByText("1,878")).toBeInTheDocument();
    expect(screen.getByText("Primary mortgage")).toBeInTheDocument();
    expect(screen.getAllByText("Tax assessed").length).toBe(2);
    expect(screen.getByText("RentCast estimate")).toBeInTheDocument();
  });

  it("flags assessed values as reference-only, not market value", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByText("Primary residence"));

    expect(await screen.findByText(/never used as the property/i)).toBeInTheDocument();
    expect(screen.getAllByText("Reference").length).toBe(2);
  });

  it("records a manually entered valuation", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByText("Primary residence"));
    await user.type(await screen.findByLabelText(/^Value/), "950000");
    await user.click(screen.getByRole("button", { name: /Add valuation/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith(
        "/real_estate_properties/p1/valuations",
        expect.objectContaining({ amount: "950000" }),
      );
    });
  });

  it("refreshes on demand", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByText("Primary residence"));
    await user.click(await screen.findByRole("button", { name: /Refresh now/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/real_estate_properties/p1/refresh", {});
    });
  });

  it("deletes the property (with confirm) and returns to the list", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByText("Primary residence"));
    await screen.findByText("Value history");

    await user.click(screen.getByRole("button", { name: "Page actions" }));
    await user.click(await screen.findByRole("menuitem", { name: /Delete property/i }));

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Delete Primary residence?")).toBeInTheDocument();
    expect(within(dialog).getByText(/linked mortgage is kept/)).toBeInTheDocument();

    mockRoutes(UNCONFIGURED);
    await user.click(within(dialog).getByRole("button", { name: "Delete property" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/real_estate_properties/p1");
    });
    expect(await screen.findByText("No properties yet.")).toBeInTheDocument();
  });

  // ── Gap closed by the frontend/API interaction audit ───────────────────────

  it("deletes a valuation (with confirm) via DELETE /real_estate_properties/:id/valuations/:valuation_id", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByText("Primary residence"));

    const del = await screen.findByLabelText(`Delete ${formatDate("2026-07-20")} valuation`);
    await user.click(del);

    const dialog = await screen.findByRole("alertdialog");
    expect(within(dialog).getByText("Delete this valuation?")).toBeInTheDocument();
    await user.click(within(dialog).getByRole("button", { name: "Delete" }));

    await waitFor(() => {
      expect(apiMock.delete).toHaveBeenCalledWith("/real_estate_properties/p1/valuations/v4");
    });
  });

  it("keeps the valuation when the confirm is declined", async () => {
    const user = userEvent.setup();
    renderApp({ initialPath: PATH, initialToken: "tok" });

    await user.click(await screen.findByText("Primary residence"));
    await user.click(await screen.findByLabelText(`Delete ${formatDate("2026-07-20")} valuation`));

    const dialog = await screen.findByRole("alertdialog");
    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));

    await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
    expect(apiMock.delete).not.toHaveBeenCalled();
  });
});
