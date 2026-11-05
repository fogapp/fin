import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, fireEvent, waitFor } from "@testing-library/react";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { renderWithRouter } from "@/test/queryClient";
import { HoldingDrawer } from "./HoldingDrawer";
import type { HoldingRow } from "./types";

const apiMock = vi.mocked(api);

function makeHolding(overrides: Partial<HoldingRow> = {}): HoldingRow {
  return {
    id: "h-1",
    security_id: "sec-1",
    ticker: "VMFXX",
    name: "Vanguard Federal MMF",
    cusip: "922906300",
    label: null,
    quantity: 10,
    price: 1,
    market_value: 10,
    cost_basis: 10,
    unrealized_gl: 0,
    unrealized_gl_pct: 0,
    asset_class: "Cash",
    est_annual_income: null,
    dividend_yield: null,
    as_of_date: "2026-06-30",
    ...overrides,
  };
}

function renderDrawer(holding: HoldingRow = makeHolding()) {
  return renderWithRouter(<HoldingDrawer holding={holding} onClose={() => {}} />);
}

describe("HoldingDrawer — label editing", () => {
  beforeEach(() => {
    apiMock.patch.mockReset();
    apiMock.patch.mockResolvedValue({ security_id: "sec-1", label: "Emergency fund" });
  });

  it("saves once when Enter blurs the input", async () => {
    renderDrawer();
    const input = screen.getByLabelText("Label");
    fireEvent.change(input, { target: { value: "Emergency fund" } });
    fireEvent.keyDown(input, { key: "Enter" });
    fireEvent.blur(input);

    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledTimes(1));
    expect(apiMock.patch).toHaveBeenCalledWith("/security_labels/sec-1", { label: "Emergency fund" });
  });

  it("saves on blur alone", async () => {
    renderDrawer();
    fireEvent.change(screen.getByLabelText("Label"), { target: { value: "Emergency fund" } });
    fireEvent.blur(screen.getByLabelText("Label"));

    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledTimes(1));
  });

  it("does not save when the value is unchanged", () => {
    renderDrawer(makeHolding({ label: "Emergency fund" }));
    fireEvent.blur(screen.getByLabelText("Label"));
    expect(apiMock.patch).not.toHaveBeenCalled();
  });

  it("clears the label with an empty value", async () => {
    renderDrawer(makeHolding({ label: "Emergency fund" }));
    const input = screen.getByLabelText("Label");
    fireEvent.change(input, { target: { value: "   " } });
    fireEvent.blur(input);

    await waitFor(() =>
      expect(apiMock.patch).toHaveBeenCalledWith("/security_labels/sec-1", { label: "" }),
    );
  });

  it("reverts the draft on Escape without saving", () => {
    renderDrawer(makeHolding({ label: "Emergency fund" }));
    const input = screen.getByLabelText("Label");
    fireEvent.change(input, { target: { value: "Something else" } });
    fireEvent.keyDown(input, { key: "Escape" });
    fireEvent.blur(input);

    expect(input).toHaveValue("Emergency fund");
    expect(apiMock.patch).not.toHaveBeenCalled();
  });

  it("retries after a failed save instead of going quiet", async () => {
    apiMock.patch.mockRejectedValueOnce(new Error("boom"));
    renderDrawer();
    const input = screen.getByLabelText("Label");

    fireEvent.change(input, { target: { value: "Emergency fund" } });
    fireEvent.blur(input);
    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledTimes(1));

    fireEvent.blur(input);
    await waitFor(() => expect(apiMock.patch).toHaveBeenCalledTimes(2));
  });

  it("refuses to send a request for a holding with no security_id", () => {
    renderDrawer(makeHolding({ security_id: undefined as unknown as string }));
    const input = screen.getByLabelText("Label");
    fireEvent.change(input, { target: { value: "Emergency fund" } });
    fireEvent.blur(input);

    expect(apiMock.patch).not.toHaveBeenCalled();
    expect(screen.getByText(/reload the page/i)).toBeInTheDocument();
  });
});
