import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { renderWithClient } from "@/test/queryClient";
import { TimeZoneCard } from "./TimeZoneCard";

const apiMock = vi.mocked(api);

const SETTINGS = {
  time_zone: "America/Los_Angeles",
  time_zones: [
    { id: "America/Los_Angeles", name: "Pacific Time (US & Canada)", utc_offset: "-08:00" },
    { id: "America/New_York", name: "Eastern Time (US & Canada)", utc_offset: "-05:00" },
    { id: "Europe/Amsterdam", name: "Amsterdam", utc_offset: "+01:00" },
  ],
};

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.patch.mockReset();
  apiMock.get.mockResolvedValue(SETTINGS as never);
});

describe("TimeZoneCard", () => {
  it("shows the current zone", async () => {
    renderWithClient(<TimeZoneCard isAdmin />);
    expect(await screen.findByDisplayValue("America/Los Angeles")).toBeInTheDocument();
    expect(apiMock.get).toHaveBeenCalledWith("/instance_settings");
  });

  it("lets an admin search by Rails name and pick a zone", async () => {
    apiMock.patch.mockResolvedValue({ ...SETTINGS, time_zone: "America/New_York" } as never);
    renderWithClient(<TimeZoneCard isAdmin />);
    const input = await screen.findByRole("textbox", { name: "Time zone" });

    const user = userEvent.setup();
    await user.clear(input);
    await user.type(input, "eastern");
    expect(screen.queryByText("Europe/Amsterdam")).toBeNull();
    await user.click(await screen.findByText("America/New York"));

    await waitFor(() => {
      expect(apiMock.patch).toHaveBeenCalledWith("/instance_settings", { time_zone: "America/New_York" });
    });
    expect(await screen.findByText("Time zone set to America/New_York")).toBeInTheDocument();
  });

  it("is read-only for a non-admin", async () => {
    renderWithClient(<TimeZoneCard isAdmin={false} />);
    expect(await screen.findByText("America/Los Angeles")).toBeInTheDocument();
    expect(screen.queryByRole("textbox", { name: "Time zone" })).toBeNull();
    expect(screen.getByText(/Only a household admin can change it/)).toBeInTheDocument();
  });
});
