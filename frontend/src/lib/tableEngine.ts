/**
 * The shared row engine behind TransactionTable and
 * InvestmentTransactionTable: turning one page of already-sorted items into
 * the rendered row list — group header rows interleaved with item rows,
 * collapsed groups hidden but still counted.
 *
 * Pure functions only (like lib/transactionTable.ts): the tables keep the
 * state and markup, this keeps the algorithm both of them used to duplicate.
 */

export type GroupedRow<T> =
  | { type: "header"; label: string; count: number }
  /** `group` is the owning header's label; `pIdx` numbers the *rendered* item
   *  rows in order (collapsed rows are skipped) — TransactionTable uses it
   *  for shift-click checkbox ranges over the paginated array. */
  | { type: "tx"; tx: T; group: string; pIdx: number };

/**
 * Builds the row list for one page of items. Items are expected to arrive
 * pre-sorted with same-group items adjacent (the group-aware sort's job);
 * a group's header row gets its count back-patched once the group's size is
 * known, and counts include rows hidden by collapse — the header still says
 * how many rows it's hiding.
 */
export function buildGroupedRows<T>({ items, groupKey, groupLabel = (key) => key, collapsed }: {
  items: T[];
  /** null → no grouping: one item row per item, no headers. */
  groupKey: ((item: T) => string) | null;
  /** Display label for a group key (default: the key itself). Labels are the
   *  group identity here: adjacency and the `collapsed` set both use them. */
  groupLabel?: (key: string) => string;
  collapsed: Set<string>;
}): GroupedRow<T>[] {
  if (!groupKey) return items.map((tx, i) => ({ type: "tx" as const, tx, group: "", pIdx: i }));

  let lastLabel = "";
  let currentCount = 0;
  let txPIdx = 0;
  let openHeader: { type: "header"; label: string; count: number } | null = null;
  const result: GroupedRow<T>[] = [];
  for (const tx of items) {
    const label = groupLabel(groupKey(tx));
    if (label !== lastLabel) {
      if (openHeader) openHeader.count = currentCount;
      openHeader = { type: "header", label, count: 0 };
      result.push(openHeader);
      lastLabel = label;
      currentCount = 0;
    }
    if (!collapsed.has(label)) result.push({ type: "tx", tx, group: label, pIdx: txPIdx++ });
    currentCount++;
  }
  if (openHeader) openHeader.count = currentCount;
  return result;
}

/** A new Set with `value` toggled — the collapse/expand state update both
 *  tables run from their group-header click handlers. */
export function toggledSet<T>(set: Set<T>, value: T): Set<T> {
  const next = new Set(set);
  if (next.has(value)) next.delete(value);
  else next.add(value);
  return next;
}
