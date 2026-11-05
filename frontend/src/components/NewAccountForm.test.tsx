import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, waitFor, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithClient } from "@/test/queryClient";

vi.mock("@/api/client", () => ({ api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() } }));

const plaidOpen = vi.fn();
const plaidGlobal = globalThis as typeof globalThis & { __plaid_onSuccess?: (t: string) => void };
vi.mock("react-plaid-link", () => ({
  usePlaidLink: (opts: { token: string | null; onSuccess: (t: string) => void }) => {
    // Expose the onSuccess so the test can fire a fake Plaid completion.
    plaidGlobal.__plaid_onSuccess = opts.onSuccess;
    return { open: plaidOpen, ready: !!opts.token };
  },
}));

import { api } from "@/api/client";
import { NewAccountForm } from "./NewAccountForm";

const apiMock = vi.mocked(api);

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  plaidOpen.mockReset();
  // /accounts list query consumed by ManualForm via queries.brokers()
  apiMock.get.mockResolvedValue([
    { id: "b-1", name: "Schwab" },
    { id: "b-2", name: "Fidelity" },
  ] as never);
  apiMock.post.mockResolvedValue({ link_token: "link-token-1" } as never);
});

describe("NewAccountForm — Choose step", () => {
  it("renders the Plaid prompt and disables the button until the link token loads", async () => {
    renderWithClient(<NewAccountForm onClose={() => {}} />);

    expect(screen.getByText(/Connect your bank with Plaid/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Preparing Plaid…/i })).toBeDisabled();

    // After /plaid/link_token resolves, the button becomes Connect with Plaid
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /Connect with Plaid/i })).not.toBeDisabled(),
    );
  });

  it("opens Plaid Link when the Connect button is clicked", async () => {
    renderWithClient(<NewAccountForm onClose={() => {}} />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /Connect with Plaid/i })).not.toBeDisabled(),
    );
    await userEvent.setup().click(screen.getByRole("button", { name: /Connect with Plaid/i }));
    expect(plaidOpen).toHaveBeenCalled();
  });

  it("exchanges the public_token on Plaid success and closes the modal", async () => {
    apiMock.post.mockImplementation((path: string) => {
      if (path === "/plaid/link_token") return Promise.resolve({ link_token: "link-token-1" } as never);
      if (path === "/plaid/items") return Promise.resolve({ id: "item-1" } as never);
      return Promise.resolve({} as never);
    });

    const onClose = vi.fn();
    renderWithClient(<NewAccountForm onClose={onClose} />);

    await waitFor(() => expect(plaidGlobal.__plaid_onSuccess).toBeTypeOf("function"));
    plaidGlobal.__plaid_onSuccess!("public-token-abc");

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/plaid/items", { public_token: "public-token-abc" });
      expect(onClose).toHaveBeenCalled();
    });
  });

  it("offers the manual fallback", async () => {
    renderWithClient(<NewAccountForm onClose={() => {}} />);
    await userEvent.setup().click(screen.getByText(/add an account manually instead/i));
    expect(await screen.findByText("New account")).toBeInTheDocument();
  });
});

describe("NewAccountForm — Manual step", () => {
  async function openManual() {
    const view = renderWithClient(<NewAccountForm onClose={() => {}} />);
    await userEvent.setup().click(screen.getByText(/add an account manually instead/i));
    await waitFor(() => expect(screen.getByText("New account")).toBeInTheDocument());
    return view;
  }

  it("loads brokers into the select", async () => {
    await openManual();
    await waitFor(() => {
      expect(screen.getByRole("option", { name: "Schwab" })).toBeInTheDocument();
      expect(screen.getByRole("option", { name: "Fidelity" })).toBeInTheDocument();
    });
  });

  it("validates that name is required before submitting", async () => {
    await openManual();
    await userEvent.setup().click(screen.getByRole("button", { name: /create account/i }));
    expect(await screen.findByText(/Name is required/)).toBeInTheDocument();
    expect(apiMock.post).not.toHaveBeenCalledWith("/accounts", expect.anything());
  });

  it("validates that broker is required before submitting", async () => {
    await openManual();
    const user = userEvent.setup();
    await user.type(screen.getByPlaceholderText(/e.g. Fidelity Brokerage/i), "My Acct");
    await user.click(screen.getByRole("button", { name: /create account/i }));
    expect(await screen.findByText(/Broker is required/)).toBeInTheDocument();
  });

  it("submits the account creation payload on success", async () => {
    apiMock.post.mockImplementation((path: string, body?: unknown) => {
      if (path === "/plaid/link_token") return Promise.resolve({ link_token: "lt" } as never);
      if (path === "/accounts") return Promise.resolve({ id: "acc-new", name: (body as { name: string }).name } as never);
      return Promise.resolve({} as never);
    });

    const onCreated = vi.fn();
    const onClose = vi.fn();
    renderWithClient(<NewAccountForm onClose={onClose} onCreated={onCreated} />);
    const user = userEvent.setup();
    await user.click(screen.getByText(/add an account manually instead/i));

    await waitFor(() => expect(screen.getByRole("option", { name: "Schwab" })).toBeInTheDocument());
    await user.type(screen.getByPlaceholderText(/e.g. Fidelity Brokerage/i), "My Brokerage");
    // The dialog renders in a portal, so query via screen (broker select, then type select)
    const selects = screen.getAllByRole("combobox");
    fireEvent.change(selects[0], { target: { value: "b-1" } });
    fireEvent.change(selects[1], { target: { value: "Checking" } });
    await user.type(screen.getByPlaceholderText(/Last 4 digits/i), "1234");

    await user.click(screen.getByRole("button", { name: /create account/i }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/accounts", {
        name: "My Brokerage",
        account_number: "1234",
        account_type: "Checking",
        broker_id: "b-1",
      });
      expect(onCreated).toHaveBeenCalledWith(expect.objectContaining({ id: "acc-new" }));
      expect(onClose).toHaveBeenCalled();
    });
  });

  it("creates a new broker inline and selects it", async () => {
    apiMock.post.mockImplementation((path: string, body?: unknown) => {
      if (path === "/plaid/link_token") return Promise.resolve({ link_token: "lt" } as never);
      if (path === "/brokers") return Promise.resolve({ id: "b-new", name: (body as { name: string }).name } as never);
      return Promise.resolve({} as never);
    });

    await openManual();
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: /^\+ New$/ }));
    await user.type(screen.getByPlaceholderText("Broker name"), "New Broker");
    await user.click(screen.getByRole("button", { name: /^Add$/ }));

    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/brokers", { name: "New Broker" });
    });
  });

  it("surfaces the API error message when account creation fails", async () => {
    apiMock.post.mockImplementation((path: string) => {
      if (path === "/plaid/link_token") return Promise.resolve({ link_token: "lt" } as never);
      if (path === "/accounts") return Promise.reject(new Error("Boom"));
      return Promise.resolve({} as never);
    });

    await openManual();
    const user = userEvent.setup();
    await waitFor(() => expect(screen.getByRole("option", { name: "Schwab" })).toBeInTheDocument());
    await user.type(screen.getByPlaceholderText(/e.g. Fidelity Brokerage/i), "x");
    const selects = screen.getAllByRole("combobox");
    fireEvent.change(selects[0], { target: { value: "b-1" } });
    await user.click(screen.getByRole("button", { name: /create account/i }));

    expect(await screen.findByText("Boom")).toBeInTheDocument();
  });
});
