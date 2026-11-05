import { useMemo } from "react";

/**
 * Slice `items` to one page. `page` is zero-based and clamped to the last
 * page, so a filter that shrinks the list never strands the view on an empty
 * page past the end. Page state stays with the caller, which also knows when
 * to reset it (a new filter, sort or search).
 */
export function usePagination<T>(items: T[], page: number, pageSize: number) {
  const totalPages = Math.ceil(items.length / pageSize);
  const current = Math.max(0, Math.min(page, totalPages - 1));
  const pageItems = useMemo(
    () => items.slice(current * pageSize, (current + 1) * pageSize),
    [items, current, pageSize],
  );
  return { page: current, pageItems, totalPages };
}
