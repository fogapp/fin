import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { screen, fireEvent, waitFor, within } from "@testing-library/react";
import { renderWithClient } from "@/test/queryClient";
import type { ImportPreview } from "@/api/types";

vi.mock("@/api/client", () => ({ getToken: () => "test-token", api: { get: vi.fn(), post: vi.fn() } }));

import { api } from "@/api/client";
import { CsvUploadModal } from "./CsvUploadModal";

const apiGet = vi.mocked(api.get);

function csvFile(name: string, body = "Date,Description,Amount\n2026-01-01,Coffee,-1.00\n") {
  return new File([ body ], name, { type: "text/csv" });
}

function jsonResponse(body: unknown, { status = 200 }: { status?: number } = {}) {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(body),
  } as Response);
}

const COLUMNS = [
  { name: "Date", required: true, found: "Date" },
  { name: "Description", required: true, found: "Description" },
  { name: "Amount", required: true, found: "Amount" },
  { name: "Post Date", required: false, found: null },
];

function readyPreview(overrides: Partial<ImportPreview> = {}): ImportPreview {
  return {
    format: "spreadsheet", format_label: "Spreadsheet", ready: true,
    headers: [ "Date", "Description", "Amount" ], row_count: 3, invalid_row_count: 1,
    imports_as: "bank", columns: COLUMNS, suggestions: [],
    problems: [ { row: 4, message: "“soon” in Date isn't a date Fin reads (use 01/31/2026 or 2026-01-31)" } ],
    sample: [ { row: 2, date: "2026-01-15", description: "Coffee", amount: -4.5, type: "Sale" } ],
    ...overrides,
  };
}

const UNKNOWN_PREVIEW: ImportPreview = {
  format: "unknown", format_label: "Unrecognized", ready: false,
  headers: [ "When", "Payee", "Amt" ], row_count: 0, invalid_row_count: 0, imports_as: null,
  columns: COLUMNS.map((c) => ({ ...c, found: null })),
  suggestions: [ { from: "Payee", to: "Description" }, { from: "Amt", to: "Amount" } ],
  problems: [ { row: null, message: "Unrecognized file. Row 1 has When, Payee, Amt; a spreadsheet import needs Date, Description, Amount as well." } ],
  sample: [],
};

const IMPORT_DONE = {
  id: "imp-1", status: "completed", kind: "spreadsheet",
  imported_count: 2, skipped_count: 0, error_count: 1,
  error_log: "- soon Tea: “soon” in Date isn't a date", source_filename: "a.csv",
};

describe("CsvUploadModal", () => {
  let fetchMock: ReturnType<typeof vi.fn>;
  let previews: Record<string, ImportPreview>;

  beforeEach(() => {
    previews = {};
    apiGet.mockReset();
    apiGet.mockImplementation(async (path: string) => {
      if (path === "/office/configuration") return { configured: false } as never;
      return undefined as never;
    });
    fetchMock = vi.fn((url: string, init: RequestInit) => {
      if (url === "/api/v1/imports/preview") {
        const file = (init.body as FormData).get("file") as File;
        return jsonResponse(previews[file.name] ?? readyPreview());
      }
      return jsonResponse(IMPORT_DONE, { status: 201 });
    });
    vi.stubGlobal("fetch", fetchMock);
  });

  afterEach(() => vi.unstubAllGlobals());

  function render(onClose = () => {}) {
    return renderWithClient(<CsvUploadModal accountId="a1" accountName="Checking ****1234" onClose={onClose} />);
  }

  function addFile(file: File) {
    fireEvent.change(screen.getByLabelText("Choose CSV files"), { target: { files: [ file ] } });
  }

  it("renders the header, the account and the drop zone", () => {
    render();
    expect(screen.getByText("Import transactions")).toBeInTheDocument();
    expect(screen.getByText("Checking ****1234")).toBeInTheDocument();
    expect(screen.getByText(/Drop CSV files here/)).toBeInTheDocument();
  });

  it("calls onClose when the close button is clicked", () => {
    const onClose = vi.fn();
    render(onClose);
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalled();
  });

  it("checks an added file with the server and summarizes it", async () => {
    render();
    addFile(csvFile("ledger.csv"));

    expect(screen.getByText("ledger.csv")).toBeInTheDocument();
    expect(await screen.findByText("Spreadsheet · 2 rows · 1 won't import")).toBeInTheDocument();
    const previewCall = fetchMock.mock.calls.find(([ url ]) => url === "/api/v1/imports/preview")!;
    expect((previewCall[1].body as FormData).get("account_id")).toBe("a1");
    expect(screen.getByRole("button", { name: "Import 1 file" })).toBeEnabled();
  });

  it("shows the row problems and sample when a file's details are opened", async () => {
    render();
    addFile(csvFile("ledger.csv"));
    fireEvent.click(await screen.findByRole("button", { name: "Show details for ledger.csv" }));

    expect(screen.getByText("1 row won't import", { exact: false })).toBeInTheDocument();
    expect(screen.getByText("Row 4")).toBeInTheDocument();
    expect(screen.getByText("How the first rows will import")).toBeInTheDocument();
    expect(screen.getByText("Coffee")).toBeInTheDocument();
  });

  it("explains a file in no known format: missing columns, renames, and the format guide", async () => {
    previews["bank.csv"] = UNKNOWN_PREVIEW;
    apiGet.mockImplementation(async (path: string) => {
      if (path === "/imports/spreadsheet_format") {
        return {
          columns: [ { name: "Date", required: true, description: "When it happened", example: "01/31/2026" } ],
          split_amount: "Debit and Credit work too.",
          notes: [ "Column names go in row 1." ],
        } as never;
      }
      return { configured: false } as never;
    });
    render();
    addFile(csvFile("bank.csv", "When,Payee,Amt\n"));

    expect(await screen.findByText("Not in a format Fin can import yet")).toBeInTheDocument();
    expect(screen.getByText("Rename these headers in row 1:")).toBeInTheDocument();
    expect(screen.getByText("Payee")).toBeInTheDocument();
    expect(within(screen.getByRole("list", { name: "Columns" })).getAllByText("missing, required")).toHaveLength(3);
    expect(screen.getByRole("button", { name: "Import" })).toBeDisabled();
    // The guide opens on its own with the layout to follow.
    expect(await screen.findByText("When it happened")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Download template/ })).toBeInTheDocument();
  });

  it("explains an Excel workbook instead of ignoring it, and ignores other files", () => {
    render();
    fireEvent.change(screen.getByLabelText("Choose CSV files"), {
      target: { files: [ new File([ "x" ], "ledger.xlsx"), new File([ "x" ], "image.png", { type: "image/png" }) ] },
    });

    expect(screen.getByText("ledger.xlsx")).toBeInTheDocument();
    expect(screen.getByText(/Save it as CSV UTF-8/)).toBeInTheDocument();
    expect(screen.queryByText("image.png")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("de-duplicates by filename", () => {
    render();
    addFile(csvFile("a.csv"));
    addFile(csvFile("a.csv"));
    expect(screen.getAllByText("a.csv")).toHaveLength(1);
  });

  it("imports the files that passed the check and shows the result", async () => {
    render();
    addFile(csvFile("a.csv"));
    fireEvent.click(await screen.findByRole("button", { name: "Import 1 file" }));

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/v1/imports",
        expect.objectContaining({ method: "POST", headers: { Authorization: "Bearer test-token" } }),
      );
    });
    expect(await screen.findByText("2 imported")).toBeInTheDocument();
    expect(screen.getByText(/isn't a date/)).toBeInTheDocument();
  });

  it("shows why an import failed rather than its HTTP status", async () => {
    fetchMock.mockImplementation((url: string) => url === "/api/v1/imports/preview"
      ? jsonResponse(readyPreview())
      : jsonResponse({ ...IMPORT_DONE, status: "failed", error_log: "Unrecognized file. Row 1 has foo" }, { status: 422 }));
    render();
    addFile(csvFile("garbage.csv"));
    fireEvent.click(await screen.findByRole("button", { name: "Import 1 file" }));

    expect(await screen.findByText("Unrecognized file. Row 1 has foo")).toBeInTheDocument();
  });

  describe("from Office", () => {
    beforeEach(() => {
      apiGet.mockImplementation(async (path: string) => {
        if (path === "/office/configuration") return { configured: true } as never;
        if (path.startsWith("/office/spreadsheets?") || path === "/office/spreadsheets") {
          return [ { id: 9, title: "Ledger 2019", folder: "Finances", updated_at: null, url: "https://office.test/d/9" } ] as never;
        }
        if (path.startsWith("/office/spreadsheets/9/preview")) {
          return {
            id: 9, title: "Ledger 2019", folder: "Finances", updated_at: null, url: "https://office.test/d/9",
            sheets: [ { name: "2019", used_range: "A1:C4" }, { name: "2020", used_range: "A1:C9" } ],
            sheet: "2019",
            preview: readyPreview(),
          } as never;
        }
        return undefined as never;
      });
    });

    it("opens on the Office tab, checks the picked sheet, and imports it", async () => {
      fetchMock.mockImplementation(() => jsonResponse(IMPORT_DONE, { status: 201 }));
      render();

      fireEvent.click(await screen.findByRole("button", { name: /Ledger 2019/ }));
      expect(await screen.findByText("Spreadsheet · 2 rows ready to import as bank activity", { exact: false })).toBeInTheDocument();
      expect(apiGet).toHaveBeenCalledWith("/office/spreadsheets/9/preview?account_id=a1", expect.anything());
      expect(screen.getByLabelText("Sheet")).toHaveValue("2019");

      fireEvent.click(screen.getByRole("button", { name: "Import 2 rows" }));

      await waitFor(() => {
        const call = fetchMock.mock.calls.find(([ url ]) => url === "/api/v1/office/spreadsheets/9/import")!;
        expect(JSON.parse(call[1].body as string)).toEqual({ account_id: "a1", sheet: "2019" });
      });
      expect(await screen.findByText("Imported “Ledger 2019”", { exact: false })).toBeInTheDocument();
    });

    it("re-checks another sheet of the spreadsheet when it's picked", async () => {
      render();
      fireEvent.click(await screen.findByRole("button", { name: /Ledger 2019/ }));
      fireEvent.change(await screen.findByLabelText("Sheet"), { target: { value: "2020" } });

      await waitFor(() =>
        expect(apiGet).toHaveBeenCalledWith("/office/spreadsheets/9/preview?account_id=a1&sheet=2020", expect.anything()),
      );
    });

    it("can switch to uploading a CSV", async () => {
      render();
      fireEvent.click(await screen.findByRole("tab", { name: "Upload CSV" }));
      expect(screen.getByText(/Drop CSV files here/)).toBeInTheDocument();
    });
  });
});
