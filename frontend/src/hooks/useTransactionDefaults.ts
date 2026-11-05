import type { ColumnKey, GroupByKey, SortOption } from "@/components/FilterBar";
import { DEFAULT_SEARCH_ENGINE } from "@/lib/searchEngines";
import { usePreferences } from "./usePreferences";

const DEFAULT_COLUMNS: ColumnKey[] = ["date", "description", "merchant", "category", "amount", "tags", "note"];
const DEFAULT_PRIMARY_SORT: SortOption = { field: "date", dir: "desc" };
export const PAGE_SIZE_OPTIONS = [25, 50, 100, 250] as const;
export type PageSizeOption = typeof PAGE_SIZE_OPTIONS[number];
const DEFAULT_PAGE_SIZE: PageSizeOption = 250;

function readLs<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

export function useTransactionDefaults() {
  const { prefs, set } = usePreferences();

  // Read from DB prefs when available, fall back to localStorage for first render
  const txn = (prefs.transactions as Record<string, unknown> | undefined) ?? {};

  const columns        = (txn.columns        as ColumnKey[]    | undefined) ?? readLs("txn-default-columns",               DEFAULT_COLUMNS);
  const primarySort    = (txn.primary_sort   as SortOption     | undefined) ?? readLs("txn-default-primary-sort",         DEFAULT_PRIMARY_SORT);
  const secondarySort  = (txn.secondary_sort as SortOption | null | undefined) ?? readLs<SortOption | null>("txn-default-secondary-sort", null);
  const groupBy        = (txn.group_by       as GroupByKey     | undefined) ?? readLs<GroupByKey>("txn-default-group-by",  "month");
  const pageSize       = (txn.page_size      as PageSizeOption | undefined) ?? readLs("txn-default-page-size",            DEFAULT_PAGE_SIZE);
  const combineMerchantDesc = (txn.combine_merchant_desc as boolean | undefined) ?? readLs("txn-default-combine-merchant-desc", true);
  const codeStyleFallback   = (txn.code_style_fallback   as boolean | undefined) ?? readLs("txn-default-code-style-fallback",   true);
  const showTransfers       = (txn.show_transfers        as boolean | undefined) ?? readLs("txn-default-show-transfers",        false);
  const showCheckboxes      = (txn.show_checkboxes       as boolean | undefined) ?? readLs("txn-default-show-checkboxes",       false);
  const searchEngine        = (txn.search_engine         as string  | undefined) ?? readLs("txn-default-search-engine",         DEFAULT_SEARCH_ENGINE);

  function patch(next: Record<string, unknown>) {
    set("transactions", { ...txn, ...next });
  }

  function setColumns(v: ColumnKey[]) {
    localStorage.setItem("txn-default-columns", JSON.stringify(v));
    patch({ columns: v });
  }
  function setPrimarySort(v: SortOption) {
    localStorage.setItem("txn-default-primary-sort", JSON.stringify(v));
    patch({ primary_sort: v });
  }
  function setSecondarySort(v: SortOption | null) {
    localStorage.setItem("txn-default-secondary-sort", JSON.stringify(v));
    patch({ secondary_sort: v });
  }
  function setGroupBy(v: GroupByKey) {
    localStorage.setItem("txn-default-group-by", JSON.stringify(v));
    patch({ group_by: v });
  }
  function setPageSize(v: PageSizeOption) {
    localStorage.setItem("txn-default-page-size", JSON.stringify(v));
    patch({ page_size: v });
  }
  function setCombineMerchantDesc(v: boolean) {
    localStorage.setItem("txn-default-combine-merchant-desc", JSON.stringify(v));
    patch({ combine_merchant_desc: v });
  }
  function setCodeStyleFallback(v: boolean) {
    localStorage.setItem("txn-default-code-style-fallback", JSON.stringify(v));
    patch({ code_style_fallback: v });
  }
  function setShowTransfers(v: boolean) {
    localStorage.setItem("txn-default-show-transfers", JSON.stringify(v));
    patch({ show_transfers: v });
  }
  function setShowCheckboxes(v: boolean) {
    localStorage.setItem("txn-default-show-checkboxes", JSON.stringify(v));
    patch({ show_checkboxes: v });
  }
  function setSearchEngine(v: string) {
    localStorage.setItem("txn-default-search-engine", JSON.stringify(v));
    patch({ search_engine: v });
  }
  function reset() {
    setColumns(DEFAULT_COLUMNS);
    setPrimarySort(DEFAULT_PRIMARY_SORT);
    setSecondarySort(null);
    setGroupBy("month");
    setPageSize(DEFAULT_PAGE_SIZE);
    setCombineMerchantDesc(true);
    setCodeStyleFallback(true);
    setShowTransfers(false);
    setShowCheckboxes(false);
    setSearchEngine(DEFAULT_SEARCH_ENGINE);
  }

  return {
    columns, setColumns,
    primarySort, setPrimarySort,
    secondarySort, setSecondarySort,
    groupBy, setGroupBy,
    pageSize, setPageSize,
    combineMerchantDesc, setCombineMerchantDesc,
    codeStyleFallback, setCodeStyleFallback,
    showTransfers, setShowTransfers,
    showCheckboxes, setShowCheckboxes,
    searchEngine, setSearchEngine,
    reset,
  };
}
