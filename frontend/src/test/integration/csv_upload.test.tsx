import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, fireEvent, waitFor } from "@testing-library/react";
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

const apiMock = vi.mocked(api);

/** "Import transactions" lives in the "Page actions" pencil dropdown on the
 *  account detail header; menu items render in a portal on document.body. */
async function clickImportCsv() {
  await userEvent.setup().click(await screen.findByRole("button", { name: /Page actions/i }));
  fireEvent.click(await screen.findByRole("menuitem", { name: /Import transactions/i }));
}

const READY_PREVIEW = {
  format: "credit_card", format_label: "Credit card export", ready: true,
  headers: [], row_count: 3, invalid_row_count: 0, imports_as: null,
  columns: [], suggestions: [], problems: [], sample: [],
};

/** Every added file is checked first (POST /imports/preview); `importResponse`
 *  answers the import itself. */
function routeFetch(importResponse: () => Promise<Response>) {
  const fetchMock = vi.mocked(fetch as unknown as ReturnType<typeof vi.fn>);
  fetchMock.mockImplementation((url: string) =>
    url === "/api/v1/imports/preview" ? jsonResponse(READY_PREVIEW) : importResponse());
  return fetchMock;
}

const ME_PAYLOAD = {
  user: { id: "u1", email: "x", name: "X" },
  household: { id: "h1", name: "H", role: "admin" },
};

const ACCOUNT = {
  id: "acc-1", name: "Amex CC", account_number: "1234", account_type: "Credit Card",
  broker_id: "b1", broker_name: "Amex", balance: 0, balance_currency: "USD",
  balance_usd: 0, investment_transaction_count: 0, cash_transaction_count: 0,
  transaction_count: 0, portfolio_value: 0, latest_transaction_date: null,
};

function csvFile(name: string, body = "Date,Amount\n2026-01-01,-1.00\n") {
  return new File([ body ], name, { type: "text/csv" });
}

function jsonResponse(body: unknown, { status = 200 }: { status?: number } = {}) {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(body),
  } as Response);
}

beforeEach(() => {
  clearToken();
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.patch.mockReset();
  apiMock.delete.mockReset();
  vi.stubGlobal("fetch", vi.fn());

  apiMock.post.mockResolvedValue({} as never);
  apiMock.patch.mockResolvedValue({} as never);
  apiMock.delete.mockResolvedValue({} as never);

  apiMock.get.mockImplementation(async (path: string) => {
    if (path === "/me") return ME_PAYLOAD as never;
    if (path === "/preferences") return { data: {} } as never;
    if (path === "/accounts") return [ ACCOUNT ] as never;
    if (path.startsWith("/cash_transactions?account_id=")) return [] as never;
    return [] as never;
  });
});

describe("CSV upload from the Accounts page", () => {
  it("opens the CsvUploadModal when 'Import transactions' is clicked", async () => {
    renderApp({ initialPath: "/accounts#id=acc-1", initialToken: "tok" });

    // Account name appears in the sidebar list + the detail header
    expect(await screen.findAllByText("Amex CC")).not.toHaveLength(0);

    await clickImportCsv();

    expect(await screen.findByText(/Drop CSV files here/i)).toBeInTheDocument();
  });

  it("POSTs to /api/v1/imports with the Bearer token when Upload is clicked", async () => {
    const fetchMock = routeFetch(() => jsonResponse({
      id: "imp-1", status: "completed", kind: "credit_card",
      imported_count: 3, skipped_count: 0, error_count: 0,
      error_log: null, source_filename: "statement.csv",
    }));

    renderApp({ initialPath: "/accounts#id=acc-1", initialToken: "tok" });

    await clickImportCsv();

    // The upload dialog renders in a portal, so query via screen.
    const fileInput = await screen.findByLabelText("Choose CSV files");
    fireEvent.change(fileInput, { target: { files: [ csvFile("statement.csv") ] } });

    expect(await screen.findByText("statement.csv")).toBeInTheDocument();

    fireEvent.click(await screen.findByRole("button", { name: /Import 1 file/i }));

    await waitFor(() => {
      const importsCall = fetchMock.mock.calls.find(([url]) => url === "/api/v1/imports");
      expect(importsCall).toBeTruthy();
      const opts = importsCall![1] as RequestInit;
      expect(opts.method).toBe("POST");
      expect((opts.headers as Record<string, string>).Authorization).toBe("Bearer tok");
    });
  });

  it("surfaces a server-side error when the upload fails", async () => {
    routeFetch(() => jsonResponse({ error: "Unrecognized format" }, { status: 422 }));

    renderApp({ initialPath: "/accounts#id=acc-1", initialToken: "tok" });

    await clickImportCsv();

    const fileInput = await screen.findByLabelText("Choose CSV files");
    fireEvent.change(fileInput, { target: { files: [ csvFile("garbage.csv") ] } });

    fireEvent.click(await screen.findByRole("button", { name: /Import 1 file/i }));

    expect(await screen.findByText("Unrecognized format")).toBeInTheDocument();
  });

  it("invalidates the cash_transactions cache on a successful upload", async () => {
    routeFetch(() => jsonResponse({
      id: "imp-2", status: "completed", kind: "credit_card",
      imported_count: 5, skipped_count: 0, error_count: 0,
      error_log: null, source_filename: "ok.csv",
    }));

    const { client } = renderApp({ initialPath: "/accounts#id=acc-1", initialToken: "tok" });
    const invalidateSpy = vi.spyOn(client, "invalidateQueries");

    await clickImportCsv();
    fireEvent.change(await screen.findByLabelText("Choose CSV files"), {
      target: { files: [ csvFile("ok.csv") ] },
    });
    fireEvent.click(await screen.findByRole("button", { name: /Import 1 file/i }));

    await waitFor(() => {
      expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: [ "cash_transactions" ] });
      expect(invalidateSpy).toHaveBeenCalledWith({ queryKey: [ "accounts" ] });
    });
  });
});
