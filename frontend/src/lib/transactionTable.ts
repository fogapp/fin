import type { ActiveFilter, GroupByKey, SortOption } from "@/components/FilterBar";
import type { CashTransaction } from "@/api/types";

/**
 * The pure filter / sort / group / search engine behind TransactionTable.
 *
 * It lives outside the component because it is the part with real behaviour —
 * operator semantics per field, group-aware sort ordering, multi-term search —
 * and testing it through the rendered table meant driving Radix menus to
 * exercise a comparison function. Everything here is a plain function of its
 * arguments; the component keeps the state and the markup.
 */

/** Does one filter hold for one transaction? */
function matches(t: CashTransaction, f: ActiveFilter): boolean {
  const v = f.value;
  switch (f.field) {
    case "merchant_id":
      if (f.operator === "blank") return !t.merchant_id;
      if (f.operator === "present") return !!t.merchant_id;
      return t.merchant_id === v;
    case "merchant_name":
      if (f.operator === "blank") return !t.merchant_name;
      if (f.operator === "present") return !!t.merchant_name;
      if (f.operator === "contains") return t.merchant_name?.toLowerCase().includes(v.toLowerCase()) ?? false;
      return t.merchant_name === v;
    case "transaction_date":
      if (f.operator === "month") return t.transaction_date.startsWith(v); // v = "YYYY-MM"
      if (f.operator === "gte") return t.transaction_date >= v;
      if (f.operator === "lte") return t.transaction_date <= v;
      if (f.operator === "equals") return t.transaction_date === v;
      return true;
    case "category_id":
      if (f.operator === "blank") return !t.category_id;
      if (f.operator === "present") return !!t.category_id;
      return t.category_id === v;
    case "account_id":
      if (f.operator === "blank") return !t.account_id;
      if (f.operator === "present") return !!t.account_id;
      return t.account_id === v;
    case "source":
      return t.source === v;
    case "transaction_type":
      return t.transaction_type === v;
    case "amount": {
      const a = Math.abs(t.amount), n = parseFloat(v);
      if (f.operator === "greater_than") return a > n;
      if (f.operator === "less_than") return a < n;
      if (f.operator === "equals") return a === n;
      return false;
    }
    case "description":
      if (f.operator === "contains") return t.description?.toLowerCase().includes(v.toLowerCase()) ?? false;
      if (f.operator === "equals") return t.description === v;
      return false;
    default:
      return true;
  }
}

export function applyFilters(
  txns: CashTransaction[],
  filters: ActiveFilter[],
  matchAll: boolean,
): CashTransaction[] {
  if (!filters.length) return txns;
  return txns.filter((t) => {
    const results = filters.map((f) => matches(t, f));
    return matchAll ? results.every(Boolean) : results.some(Boolean);
  });
}

/**
 * Counted payment legs (include_in_spend outflows — untracked-card proxies,
 * loan payments) stay visible even when transfers are hidden: they're part of
 * spend, so hiding them would hide counted money.
 */
export function applyTransferVisibility(
  txns: CashTransaction[],
  showTransfers: boolean,
): CashTransaction[] {
  if (showTransfers) return txns;
  return txns.filter((t) => !t.transfer_id || (t.transfer_include_in_spend && t.amount < 0));
}

/** Group key used while sorting (lowercased; ￿ sorts blanks last). */
export function sortGroupKey(tx: CashTransaction, groupBy: GroupByKey): string {
  if (groupBy === "month") return tx.transaction_date.slice(0, 7);
  if (groupBy === "merchant") return (tx.merchant_name ?? "￿").toLowerCase();
  if (groupBy === "category") return tx.category_name ? categoryPath(tx).toLowerCase() : "￿";
  return "";
}

/** Group key used for display rows. */
export function rowGroupKey(tx: CashTransaction, groupBy: GroupByKey): string {
  if (groupBy === "month") return tx.transaction_date.slice(0, 7);
  if (groupBy === "merchant") return tx.merchant_name ?? "No merchant";
  if (groupBy === "category") return tx.category_name ? categoryPath(tx) : "Uncategorized";
  return "";
}

/** "Parent › Child" — a bare subcategory name is ambiguous (Car › Gas vs Home › Gas). */
function categoryPath(tx: CashTransaction): string {
  return tx.category_parent_name ? `${tx.category_parent_name} › ${tx.category_name}` : tx.category_name ?? "";
}

function compare(a: CashTransaction, b: CashTransaction, s: SortOption): number {
  const mul = s.dir === "asc" ? 1 : -1;
  switch (s.field) {
    case "date": return mul * a.transaction_date.localeCompare(b.transaction_date);
    case "amount": return mul * (a.amount - b.amount);
    case "merchant": return mul * (a.merchant_name ?? "").localeCompare(b.merchant_name ?? "");
    case "category": return mul * (a.category_name ?? "").localeCompare(b.category_name ?? "");
    case "description": return mul * (a.description ?? "").localeCompare(b.description ?? "");
    default: return 0;
  }
}

/**
 * Sorts a copy. Group key wins over the sort fields so same-group rows stay
 * together; month groups additionally follow the date sort's direction, so
 * "date descending" puts the newest month first rather than sorting groups
 * ascending and rows descending inside them.
 */
export function sortTransactions(
  txns: CashTransaction[],
  {
    primarySort,
    secondarySort,
    groupBy,
  }: { primarySort: SortOption; secondarySort: SortOption | null; groupBy: GroupByKey },
): CashTransaction[] {
  return [...txns].sort((a, b) => {
    if (groupBy !== "none") {
      const gA = sortGroupKey(a, groupBy), gB = sortGroupKey(b, groupBy);
      if (gA !== gB) {
        const mul = groupBy === "month" && primarySort.field === "date"
          ? (primarySort.dir === "asc" ? 1 : -1)
          : 1;
        return gA < gB ? -mul : mul;
      }
    }
    const c1 = compare(a, b, primarySort);
    if (c1 !== 0) return c1;
    return secondarySort ? compare(a, b, secondarySort) : 0;
  });
}

/**
 * Every whitespace-separated term must appear somewhere in the row's text.
 * Order-preserving, so the caller can search a pre-sorted array and skip
 * re-sorting on every keystroke.
 */
export function searchTransactions(txns: CashTransaction[], query: string): CashTransaction[] {
  const q = query.trim().toLowerCase();
  if (!q) return txns;
  const terms = q.split(/\s+/);
  return txns.filter((t) => {
    const haystack = [
      t.description,
      t.merchant_name,
      t.category_name,
      Math.abs(t.amount).toFixed(2),
    ].filter(Boolean).join(" ").toLowerCase();
    return terms.every((term) => haystack.includes(term));
  });
}
