import { describe, it, expect } from "vitest";
import { renderHook } from "@testing-library/react";
import { usePagination } from "./usePagination";

const items = Array.from({ length: 25 }, (_, i) => i);

describe("usePagination", () => {
  it("slices the requested page", () => {
    const { result } = renderHook(() => usePagination(items, 1, 10));
    expect(result.current).toEqual({ page: 1, pageItems: [10, 11, 12, 13, 14, 15, 16, 17, 18, 19], totalPages: 3 });
  });

  it("clamps a page past the end to the last page", () => {
    const { result } = renderHook(() => usePagination(items, 7, 10));
    expect(result.current.page).toBe(2);
    expect(result.current.pageItems).toEqual([20, 21, 22, 23, 24]);
  });

  it("stays on page 0 for an empty list", () => {
    const { result } = renderHook(() => usePagination([], 3, 10));
    expect(result.current).toEqual({ page: 0, pageItems: [], totalPages: 0 });
  });
});
