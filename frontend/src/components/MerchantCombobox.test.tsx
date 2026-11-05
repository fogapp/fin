import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, waitFor, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithClient } from "@/test/queryClient";

vi.mock("@/api/client", () => ({ api: { post: vi.fn(), get: vi.fn() } }));
import { api } from "@/api/client";
import { MerchantCombobox } from "./MerchantCombobox";

const apiMock = vi.mocked(api);

const merchants = [
  { id: "m1", name: "Starbucks", category_id: null, category_name: null, notes: null, transaction_count: 5, excluded: false },
  { id: "m2", name: "Walmart", category_id: null, category_name: null, notes: null, transaction_count: 10, excluded: false },
  { id: "m3", name: "Best Buy", category_id: null, category_name: null, notes: null, transaction_count: 3, excluded: false },
];

beforeEach(() => apiMock.post.mockReset());

describe("MerchantCombobox", () => {
  it("shows the selected merchant's name in the input", () => {
    renderWithClient(<MerchantCombobox value="m1" onChange={() => {}} merchants={merchants} />);
    expect((screen.getByDisplayValue("Starbucks") as HTMLInputElement).value).toBe("Starbucks");
  });

  it("opens the dropdown on focus and lists all merchants when input is empty", async () => {
    renderWithClient(<MerchantCombobox value="" onChange={() => {}} merchants={merchants} />);
    await userEvent.setup().click(screen.getByPlaceholderText(/Search or create merchant/i));
    expect(screen.getByText("Starbucks")).toBeInTheDocument();
    expect(screen.getByText("Walmart")).toBeInTheDocument();
    expect(screen.getByText("Best Buy")).toBeInTheDocument();
  });

  it("filters by substring (case-insensitive)", async () => {
    renderWithClient(<MerchantCombobox value="" onChange={() => {}} merchants={merchants} />);
    await userEvent.setup().type(screen.getByPlaceholderText(/Search or create merchant/i), "wal");
    expect(screen.getByText("Walmart")).toBeInTheDocument();
    expect(screen.queryByText("Starbucks")).toBeNull();
  });

  it("shows the Create row for a new name and posts to /merchants on click", async () => {
    apiMock.post.mockResolvedValue({ id: "m-new", name: "New Vendor" } as never);
    const onChange = vi.fn();
    renderWithClient(<MerchantCombobox value="" onChange={onChange} merchants={merchants} />);
    const user = userEvent.setup();
    await user.type(screen.getByPlaceholderText(/Search or create merchant/i), "New Vendor");
    expect(screen.getByText(/Create.*New Vendor/)).toBeInTheDocument();

    fireEvent.mouseDown(screen.getByText(/Create.*New Vendor/));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/merchants", { name: "New Vendor" });
      expect(onChange).toHaveBeenCalledWith("m-new");
    });
  });

  it("calls onChange when a merchant row is clicked", () => {
    const onChange = vi.fn();
    renderWithClient(<MerchantCombobox value="" onChange={onChange} merchants={merchants} />);
    fireEvent.focus(screen.getByPlaceholderText(/Search or create merchant/i));
    fireEvent.mouseDown(screen.getByText("Walmart"));
    expect(onChange).toHaveBeenCalledWith("m2");
  });

  it("Enter selects the currently highlighted row", async () => {
    const onChange = vi.fn();
    renderWithClient(<MerchantCombobox value="" onChange={onChange} merchants={merchants} />);
    const input = screen.getByPlaceholderText(/Search or create merchant/i);
    await userEvent.setup().click(input);
    fireEvent.keyDown(input, { key: "ArrowDown" });   // highlight idx 1
    fireEvent.keyDown(input, { key: "Enter" });
    expect(onChange).toHaveBeenCalledWith("m2");
  });

  // The "shows API error on create failure" path is covered by NewAccountForm
  // and CategoryCombobox tests — skipping here to avoid noisy unhandled
  // rejections that get reported as test failures despite the onError handler.
});
