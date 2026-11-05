import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, fireEvent, waitFor, within } from "@testing-library/react";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return { ...actual, api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() } };
});

import { api } from "@/api/client";
import { renderWithClient } from "@/test/queryClient";
import { SecurityConversionsCard } from "./SecurityConversionsCard";

const apiMock = vi.mocked(api);

const CONVERSION = {
  id: "sc1",
  from_security: { id: "s-old", ticker: "SMNEY", name: "Siemens Energy Ag-Unsp" },
  to_security: { id: "s-new", ticker: "SMERY", name: "Siemens Energy AG - ADR - Sponsored" },
  effective_date: "2026-01-30", ratio: 5, status: "confirmed", source: "detected", evidence: {},
  confirmed_at: "2026-09-26T00:00:00Z", created_at: "2026-09-26T00:00:00Z",
};

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.delete.mockReset();
  apiMock.delete.mockResolvedValue({} as never);
});

describe("SecurityConversionsCard", () => {
  it("lists the security's confirmed conversions", async () => {
    apiMock.get.mockResolvedValue([ CONVERSION ] as never);

    renderWithClient(<SecurityConversionsCard securityId="s-new" />);

    expect(await screen.findByText(/5 SMERY per SMNEY share/)).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/security_conversions?security_id=s-new&status=confirmed");
  });

  it("renders nothing without conversions", async () => {
    apiMock.get.mockResolvedValue([] as never);

    const { container } = renderWithClient(<SecurityConversionsCard securityId="s-new" />);

    await waitFor(() => expect(apiMock.get).toHaveBeenCalled());
    expect(container.textContent).not.toContain("Conversions");
  });

  it("removes one after a confirm", async () => {
    apiMock.get.mockResolvedValue([ CONVERSION ] as never);
    renderWithClient(<SecurityConversionsCard securityId="s-new" />);

    fireEvent.click(await screen.findByRole("button", { name: /Remove conversion SMNEY to SMERY/ }));
    const dialog = await screen.findByRole("alertdialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => expect(apiMock.delete).toHaveBeenCalledWith("/security_conversions/sc1"));
  });
});
