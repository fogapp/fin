import { describe, it, expect } from "vitest";
import { renderHook, act } from "@testing-library/react";
import type { ChangeEvent, KeyboardEvent } from "react";
import { useListSearch } from "./useListSearch";

const changeEvent = (value: string) =>
  ({ target: { value } }) as ChangeEvent<HTMLInputElement>;
const keyEvent = (key: string) =>
  ({ key, preventDefault: () => {} }) as unknown as KeyboardEvent<HTMLInputElement>;

const items = [
  { id: "1", name: "Apple" },
  { id: "2", name: "Amazon" },
  { id: "3", name: "Netflix" },
  { id: "4", name: "Spotify" },
];

describe("useListSearch", () => {
  it("returns all items when search is empty", () => {
    const { result } = renderHook(() => useListSearch(items));
    expect(result.current.filtered).toEqual(items);
  });

  it("filters items by name (case-insensitive)", () => {
    const { result } = renderHook(() => useListSearch(items));
    act(() => {
      result.current.handleChange(changeEvent("am"));
    });
    expect(result.current.filtered.map((i) => i.name)).toEqual(["Amazon"]);
  });

  it("highlights the first result on input", () => {
    const { result } = renderHook(() => useListSearch(items));
    act(() => {
      result.current.handleChange(changeEvent("a"));
    });
    expect(result.current.highlightedIndex).toBe(0);
  });

  it("resets highlightedIndex to null when search is cleared", () => {
    const { result } = renderHook(() => useListSearch(items));
    act(() => {
      result.current.handleChange(changeEvent("app"));
    });
    expect(result.current.highlightedIndex).toBe(0);
    act(() => {
      result.current.handleChange(changeEvent(""));
    });
    expect(result.current.highlightedIndex).toBeNull();
  });

  it("moves highlight down on ArrowDown", () => {
    const { result } = renderHook(() => useListSearch(items));
    act(() => {
      result.current.handleChange(changeEvent("a"));
    });
    const onSelect = vi.fn();
    act(() => {
      result.current.handleKeyDown(
        keyEvent("ArrowDown"),
        onSelect
      );
    });
    expect(result.current.highlightedIndex).toBe(1);
  });

  it("calls onSelect and blurs on Enter", () => {
    const { result } = renderHook(() => useListSearch(items));
    const onSelect = vi.fn();
    act(() => {
      result.current.handleChange(changeEvent("Netflix"));
    });
    act(() => {
      result.current.handleKeyDown(
        keyEvent("Enter"),
        onSelect
      );
    });
    expect(onSelect).toHaveBeenCalledWith(items[2]);
    expect(result.current.search).toBe("");
  });

  it("clears search and blurs on Escape", () => {
    const { result } = renderHook(() => useListSearch(items));
    const onSelect = vi.fn();
    act(() => {
      result.current.handleChange(changeEvent("app"));
    });
    act(() => {
      result.current.handleKeyDown(
        keyEvent("Escape"),
        onSelect
      );
    });
    expect(result.current.search).toBe("");
    expect(onSelect).not.toHaveBeenCalled();
  });
});
