import { describe, it, expect, beforeEach, vi } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithClient } from "@/test/queryClient";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { AccountCombobox } from "./AccountCombobox";
import type { Account } from "@/api/types";

const apiMock = vi.mocked(api);

const ACCOUNTS = [
  { id: "a1", name: "Brokerage", kind: "standard", broker_name: "Fidelity", account_number: "98761234", hidden: false },
  { id: "a2", name: "Schwab", kind: "external", broker_name: null, account_number: "ext-1234abcd", hidden: false },
  { id: "a3", name: "Hidden one", kind: "standard", broker_name: "Chase", account_number: "555", hidden: true },
] as unknown as Account[];

beforeEach(() => vi.clearAllMocks());

describe("AccountCombobox", () => {
  it("lists visible accounts with broker context and an External badge", async () => {
    renderWithClient(
      <AccountCombobox value="" onChange={() => {}} accounts={ACCOUNTS} />,
    );
    await userEvent.click(screen.getByLabelText("Account"));
    expect(await screen.findByText("Brokerage")).toBeInTheDocument();
    expect(screen.getByText("Fidelity")).toBeInTheDocument();
    expect(screen.getByText("External")).toBeInTheDocument();
    expect(screen.queryByText("Hidden one")).toBeNull();
  });

  it("filters by name or broker and selects on click", async () => {
    const onChange = vi.fn();
    renderWithClient(
      <AccountCombobox value="" onChange={onChange} accounts={ACCOUNTS} />,
    );
    await userEvent.type(screen.getByLabelText("Account"), "fidel");
    expect(await screen.findByText("Brokerage")).toBeInTheDocument();
    expect(screen.queryByText("Schwab")).toBeNull();
    await userEvent.click(screen.getByText("Brokerage"));
    expect(onChange).toHaveBeenCalledWith("a1");
  });

  it("creates an external account for an unmatched name", async () => {
    apiMock.post.mockResolvedValue({ id: "ext1", name: "Vanguard 529", kind: "external", hidden: false });
    const onChange = vi.fn();
    renderWithClient(
      <AccountCombobox value="" onChange={onChange} accounts={ACCOUNTS} />,
    );
    await userEvent.type(screen.getByLabelText("Account"), "Vanguard 529");
    await userEvent.click(await screen.findByText(/Create external account/));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/accounts", { name: "Vanguard 529", kind: "external" });
      expect(onChange).toHaveBeenCalledWith("ext1");
    });
  });

  it("searches by account number (last four) but ignores external auto-numbers", async () => {
    renderWithClient(
      <AccountCombobox value="" onChange={() => {}} accounts={ACCOUNTS} />,
    );
    // "1234" appears in Brokerage's real number AND in Schwab's auto-generated
    // "ext-" number — only the real account should match.
    await userEvent.type(screen.getByLabelText("Account"), "1234");
    expect(await screen.findByText("Brokerage")).toBeInTheDocument();
    expect(screen.queryByText("Schwab")).toBeNull();
    // The row shows the masked last-four so the match is visible.
    expect(screen.getByText("····1234")).toBeInTheDocument();
  });

  it("merges createDefaults into the create-account request", async () => {
    apiMock.post.mockResolvedValue({ id: "cc1", name: "Amex Gold", kind: "external", hidden: false });
    renderWithClient(
      <AccountCombobox value="" onChange={() => {}} accounts={ACCOUNTS} createDefaults={{ account_type: "Credit Card" }} />,
    );
    await userEvent.type(screen.getByLabelText("Account"), "Amex Gold");
    await userEvent.click(await screen.findByText(/Create external account/));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/accounts", { name: "Amex Gold", kind: "external", account_type: "Credit Card" });
    });
  });

  it("respects excludeIds", async () => {
    renderWithClient(
      <AccountCombobox value="" onChange={() => {}} accounts={ACCOUNTS} excludeIds={["a1"]} />,
    );
    await userEvent.click(screen.getByLabelText("Account"));
    expect(await screen.findByText("Schwab")).toBeInTheDocument();
    expect(screen.queryByText("Brokerage")).toBeNull();
  });
});
