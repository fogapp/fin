import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createRef } from "react";
import { SearchInput } from "./SearchInput";

describe("SearchInput", () => {
  it("renders the supplied value and placeholder", () => {
    render(<SearchInput value="hello" onChange={() => {}} onKeyDown={() => {}} placeholder="Find…" />);
    const input = screen.getByPlaceholderText("Find…") as HTMLInputElement;
    expect(input.value).toBe("hello");
  });

  it("uses the default placeholder when none is supplied", () => {
    render(<SearchInput value="" onChange={() => {}} onKeyDown={() => {}} />);
    expect(screen.getByPlaceholderText("Search…")).toBeInTheDocument();
  });

  it("forwards a ref onto the underlying input", () => {
    const ref = createRef<HTMLInputElement>();
    render(<SearchInput ref={ref} value="" onChange={() => {}} onKeyDown={() => {}} />);
    expect(ref.current).toBeInstanceOf(HTMLInputElement);
  });

  it("calls onChange and onKeyDown on user input", async () => {
    const onChange = vi.fn();
    const onKeyDown = vi.fn();
    render(<SearchInput value="" onChange={onChange} onKeyDown={onKeyDown} />);
    const user = userEvent.setup();
    const input = screen.getByPlaceholderText("Search…");
    await user.type(input, "x");
    expect(onChange).toHaveBeenCalled();
    await user.keyboard("{Escape}");
    expect(onKeyDown).toHaveBeenCalled();
  });
});
