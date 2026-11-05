import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, fireEvent, waitFor } from "@testing-library/react";
import { renderWithRouter } from "@/test/queryClient";
import { ExportToOfficeButton } from "./ExportToOfficeButton";
import type { OfficeConfiguration, OfficeSheetExport } from "@/api/types";

const get = vi.fn();
const post = vi.fn();

vi.mock("@/api/client", () => ({
  api: {
    get: (path: string) => get(path),
    post: (path: string, body?: unknown) => post(path, body),
  },
}));

const CONFIGURED: OfficeConfiguration = {
  configured: true,
  base_url: "https://office.test",
  api_key_set: true,
  source: "configuration",
  datasets: [{ key: "transactions", label: "Transactions" }],
};

function sheet(overrides: Partial<OfficeSheetExport> = {}): OfficeSheetExport {
  return {
    id: "s1",
    dataset: "transactions",
    dataset_label: "Transactions",
    title: "Transactions",
    document_id: 77,
    sheet_name: "Sheet1",
    url: "https://office.test/d/77",
    filters: {},
    row_count: 12,
    last_exported_at: "2026-09-16T10:00:00Z",
    last_error: null,
    created_at: "2026-09-16T10:00:00Z",
    ...overrides,
  };
}

function stubApi({ config = CONFIGURED, sheets = [] as OfficeSheetExport[] } = {}) {
  get.mockImplementation((path: string) => {
    if (path === "/office/configuration") return Promise.resolve(config);
    if (path.startsWith("/office/sheet_exports")) return Promise.resolve(sheets);
    return Promise.resolve(null);
  });
}

function fakeTab(): Window {
  return {
    opener: {},
    close: vi.fn(),
    location: { href: "" },
    document: { title: "", body: { textContent: "" } },
  } as unknown as Window;
}

async function openMenu() {
  const trigger = await screen.findByLabelText("Export to Office");
  fireEvent.pointerDown(trigger, { button: 0, ctrlKey: false });
  fireEvent.click(trigger);
  return trigger;
}

beforeEach(() => {
  get.mockReset();
  post.mockReset();
  vi.spyOn(window, "open").mockImplementation(() => null);
});

describe("ExportToOfficeButton", () => {
  it("renders nothing when Office isn't configured", async () => {
    stubApi({ config: { ...CONFIGURED, configured: false, base_url: null, api_key_set: false, source: null } });

    renderWithRouter(<ExportToOfficeButton dataset="transactions" />);

    await waitFor(() => expect(get).toHaveBeenCalledWith("/office/configuration"));
    expect(screen.queryByLabelText("Export to Office")).not.toBeInTheDocument();
  });

  it("doesn't ask for sheets until Office is known to be configured", async () => {
    stubApi({ config: { ...CONFIGURED, configured: false } });

    renderWithRouter(<ExportToOfficeButton dataset="transactions" />);

    await waitFor(() => expect(get).toHaveBeenCalledWith("/office/configuration"));
    expect(get).not.toHaveBeenCalledWith(expect.stringContaining("/office/sheet_exports"));
  });

  it("creates a spreadsheet with the table's filters, dropping empty ones", async () => {
    stubApi();
    post.mockResolvedValue(sheet({ title: "Transactions — Chase" }));

    renderWithRouter(
      <ExportToOfficeButton
        dataset="transactions"
        filters={{ account_id: "acc-1", search: "", show_transfers: undefined, match_all: true }}
      />,
    );
    await openMenu();
    fireEvent.click(await screen.findByText("New spreadsheet"));

    await waitFor(() =>
      expect(post).toHaveBeenCalledWith("/office/sheet_exports", {
        dataset: "transactions",
        account_id: "acc-1",
        match_all: true,
      }),
    );
    expect(await screen.findByText(/Created “Transactions — Chase”/)).toBeInTheDocument();
  });

  it("opens the new spreadsheet in a tab opened on the click", async () => {
    stubApi();
    const tab = fakeTab();
    vi.mocked(window.open).mockReturnValue(tab);
    post.mockResolvedValue(sheet({ url: "https://office.test/d/88" }));

    renderWithRouter(<ExportToOfficeButton dataset="transactions" />);
    await openMenu();
    fireEvent.click(await screen.findByText("New spreadsheet"));

    // Opened before the request resolves, so the click's activation still counts.
    expect(window.open).toHaveBeenCalledWith("", "_blank");
    expect(tab.opener).toBeNull();
    await waitFor(() => expect(tab.location.href).toBe("https://office.test/d/88"));
    expect(tab.close).not.toHaveBeenCalled();
  });

  it("closes the placeholder tab when the export fails", async () => {
    stubApi();
    const tab = fakeTab();
    vi.mocked(window.open).mockReturnValue(tab);
    post.mockRejectedValue(new Error("Office rejected the API token"));

    renderWithRouter(<ExportToOfficeButton dataset="transactions" />);
    await openMenu();
    fireEvent.click(await screen.findByText("New spreadsheet"));

    expect(await screen.findByText("Office rejected the API token")).toBeInTheDocument();
    expect(tab.close).toHaveBeenCalled();
  });

  it("lists linked sheets for this dataset and refreshes the one picked", async () => {
    stubApi({ sheets: [sheet({ id: "s9", title: "Groceries 2026" })] });
    post.mockResolvedValue(sheet({ id: "s9", title: "Groceries 2026", row_count: 20 }));

    renderWithRouter(<ExportToOfficeButton dataset="transactions" />);
    await openMenu();

    fireEvent.click(await screen.findByText("Groceries 2026"));

    await waitFor(() => expect(post).toHaveBeenCalledWith("/office/sheet_exports/s9/refresh", undefined));
    expect(await screen.findByText(/Refreshed “Groceries 2026” \(20 rows\)/)).toBeInTheDocument();
  });

  it("opens a linked sheet without refreshing it", async () => {
    stubApi({ sheets: [sheet({ id: "s9", title: "Groceries 2026" })] });

    renderWithRouter(<ExportToOfficeButton dataset="transactions" />);
    await openMenu();
    fireEvent.click(await screen.findByLabelText("Open Groceries 2026 in Office"));

    expect(window.open).toHaveBeenCalledWith("https://office.test/d/77", "_blank", "noopener");
    expect(post).not.toHaveBeenCalled();
  });

  it("surfaces an export failure as an error toast", async () => {
    stubApi();
    post.mockRejectedValue(new Error("Could not reach Office at https://office.test"));

    renderWithRouter(<ExportToOfficeButton dataset="holdings" />);
    await openMenu();
    fireEvent.click(await screen.findByText("New spreadsheet"));

    expect(await screen.findByText("Could not reach Office at https://office.test")).toBeInTheDocument();
  });

  it("scopes its sheet list to its own dataset", async () => {
    stubApi();

    renderWithRouter(<ExportToOfficeButton dataset="portfolio" />);

    await waitFor(() => expect(get).toHaveBeenCalledWith("/office/sheet_exports?dataset=portfolio"));
  });
});
