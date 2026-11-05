import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, act, fireEvent } from "@testing-library/react";
import { DeferredInput } from "./DeferredInput";

describe("DeferredInput", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("renders the initial value", () => {
    render(<DeferredInput value="hello" onCommit={() => {}} />);
    expect((screen.getByDisplayValue("hello") as HTMLInputElement).value).toBe("hello");
  });

  it("does not commit immediately when typing", () => {
    const onCommit = vi.fn();
    render(<DeferredInput value="" onCommit={onCommit} debounceMs={600} />);
    fireEvent.change(screen.getByDisplayValue(""), { target: { value: "abc" } });
    expect(onCommit).not.toHaveBeenCalled();
  });

  it("commits after debounceMs of inactivity", () => {
    const onCommit = vi.fn();
    render(<DeferredInput value="" onCommit={onCommit} debounceMs={300} />);
    fireEvent.change(screen.getByDisplayValue(""), { target: { value: "abc" } });
    act(() => { vi.advanceTimersByTime(300); });
    expect(onCommit).toHaveBeenCalledWith("abc");
  });

  it("commits immediately on blur if the value has changed", () => {
    const onCommit = vi.fn();
    render(<DeferredInput value="" onCommit={onCommit} debounceMs={5_000} />);
    const input = screen.getByDisplayValue("");
    fireEvent.change(input, { target: { value: "x" } });
    fireEvent.blur(input);
    expect(onCommit).toHaveBeenCalledWith("x");
  });

  it("does not commit on blur when the value is unchanged", () => {
    const onCommit = vi.fn();
    render(<DeferredInput value="x" onCommit={onCommit} />);
    fireEvent.blur(screen.getByDisplayValue("x"));
    expect(onCommit).not.toHaveBeenCalled();
  });

  it("blurs the input when Enter is pressed", () => {
    const onCommit = vi.fn();
    render(<DeferredInput value="" onCommit={onCommit} debounceMs={5_000} />);
    const input = screen.getByDisplayValue("") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "x" } });
    input.focus();
    fireEvent.keyDown(input, { key: "Enter" });
    expect(document.activeElement).not.toBe(input);
    expect(onCommit).toHaveBeenCalledWith("x");
  });

  it("syncs local back to the prop when value changes externally", () => {
    const { rerender } = render(<DeferredInput value="a" onCommit={() => {}} />);
    rerender(<DeferredInput value="b" onCommit={() => {}} />);
    expect((screen.getByDisplayValue("b") as HTMLInputElement).value).toBe("b");
  });
});
