import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useDebounced } from "./useDebounced";

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe("useDebounced", () => {
  it("holds the initial value until the delay elapses", () => {
    const { result } = renderHook(({ value }) => useDebounced(value, 200), {
      initialProps: { value: "a" },
    });
    expect(result.current).toBe("a");
  });

  it("commits the latest value only after the delay, resetting on each change", () => {
    const { result, rerender } = renderHook(({ value }) => useDebounced(value, 200), {
      initialProps: { value: "a" },
    });

    rerender({ value: "ab" });
    act(() => { vi.advanceTimersByTime(100); });
    expect(result.current).toBe("a"); // not yet committed

    rerender({ value: "abc" }); // resets the timer
    act(() => { vi.advanceTimersByTime(100); });
    expect(result.current).toBe("a"); // still the stale reset didn't fire

    act(() => { vi.advanceTimersByTime(100); });
    expect(result.current).toBe("abc"); // full 200ms since the last change
  });
});
