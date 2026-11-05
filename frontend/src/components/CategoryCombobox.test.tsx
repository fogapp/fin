import { describe, it, expect, vi, beforeEach } from "vitest";
import { useState } from "react";
import { screen, waitFor, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithClient } from "@/test/queryClient";

vi.mock("@/api/client", () => ({ api: { post: vi.fn(), get: vi.fn() } }));
import { api } from "@/api/client";
import { CategoryCombobox } from "./CategoryCombobox";

const apiMock = vi.mocked(api);

const categories = [
  { id: "c1", name: "Food",        parent_id: null },
  { id: "c2", name: "Groceries",   parent_id: "c1" },
  { id: "c3", name: "Restaurants", parent_id: "c1" },
  { id: "c4", name: "Travel",      parent_id: null },
];

beforeEach(() => apiMock.post.mockReset());

describe("CategoryCombobox", () => {
  it("renders the selected category's display name (Parent › Child for subs)", () => {
    renderWithClient(
      <CategoryCombobox value="c2" onChange={() => {}} categories={categories} />,
    );
    expect((screen.getByDisplayValue("Food › Groceries") as HTMLInputElement).value).toBe("Food › Groceries");
  });

  it("opens the dropdown and lists 'No category' + all categories", () => {
    renderWithClient(
      <CategoryCombobox value="" onChange={() => {}} categories={categories} />,
    );
    fireEvent.focus(screen.getByPlaceholderText(/Select category/i));
    expect(screen.getByText("No category")).toBeInTheDocument();
    expect(screen.getByText("Food")).toBeInTheDocument();
    expect(screen.getByText("Food › Groceries")).toBeInTheDocument();
  });

  it("filters by the display-name substring", async () => {
    renderWithClient(
      <CategoryCombobox value="" onChange={() => {}} categories={categories} />,
    );
    await userEvent.setup().type(screen.getByPlaceholderText(/Select category/i), "rest");
    expect(screen.getByText("Food › Restaurants")).toBeInTheDocument();
    expect(screen.queryByText("Food › Groceries")).toBeNull();
  });

  it("calls onChange with empty string when 'No category' is clicked", () => {
    const onChange = vi.fn();
    renderWithClient(
      <CategoryCombobox value="c1" onChange={onChange} categories={categories} />,
    );
    fireEvent.focus(screen.getByDisplayValue("Food"));
    fireEvent.mouseDown(screen.getByText("No category"));
    expect(onChange).toHaveBeenCalledWith("");
  });

  it("calls onChange with the category id when a row is clicked", () => {
    const onChange = vi.fn();
    renderWithClient(
      <CategoryCombobox value="" onChange={onChange} categories={categories} />,
    );
    fireEvent.focus(screen.getByPlaceholderText(/Select category/i));
    fireEvent.mouseDown(screen.getByText("Travel"));
    expect(onChange).toHaveBeenCalledWith("c4");
  });

  it("offers a Create row for an unknown name and posts to /categories", async () => {
    apiMock.post.mockResolvedValue({ id: "c-new", name: "Coffee" } as never);
    const onChange = vi.fn();
    renderWithClient(
      <CategoryCombobox value="" onChange={onChange} categories={categories} />,
    );
    await userEvent.setup().type(screen.getByPlaceholderText(/Select category/i), "Coffee");
    expect(screen.getByText(/Create.*Coffee/)).toBeInTheDocument();
    fireEvent.mouseDown(screen.getByText(/Create.*Coffee/));
    await waitFor(() => {
      expect(apiMock.post).toHaveBeenCalledWith("/categories", { name: "Coffee" });
      expect(onChange).toHaveBeenCalledWith("c-new");
    });
  });

  it("syncs the displayed name when the value prop changes externally", () => {
    function Harness() {
      const [id, setId] = useState("c1");
      return (
        <>
          <button onClick={() => setId("c4")}>switch</button>
          <CategoryCombobox value={id} onChange={() => {}} categories={categories} />
        </>
      );
    }
    renderWithClient(<Harness />);
    expect((screen.getByDisplayValue("Food") as HTMLInputElement).value).toBe("Food");
    fireEvent.click(screen.getByRole("button", { name: "switch" }));
    expect((screen.getByDisplayValue("Travel") as HTMLInputElement).value).toBe("Travel");
  });
});
