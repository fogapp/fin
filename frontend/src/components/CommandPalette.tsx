import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import * as RadixDialog from "@radix-ui/react-dialog";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import type { LucideIcon } from "lucide-react";
import { Search, Store, Tags, Tag as TagIcon, Landmark, ArrowLeftRight, CreditCard, TrendingUp } from "lucide-react";
import { queries } from "@/api/queries";
import { useDebounced } from "@/hooks/useDebounced";
import { cn, formatCurrency } from "@/lib/utils";
import type {
  SearchResults, SearchMerchantResult, SearchCategoryResult, SearchTagResult,
  SearchAccountResult, SearchTransactionResult, SearchLoanResult,
  SearchInvestmentTransactionResult, SearchSecurityResult,
} from "@/api/types";

// ── Cmd+K search overlay ─────────────────────────────────────────────────────
// One flat, keyboard-navigable list built from GET /search's eight grouped
// result arrays — `flat` is the single source of truth for both rendering
// (grouped by type) and Up/Down/Enter navigation (indexed across the whole
// list), so the two can never drift out of sync with each other.

type FlatItem =
  | { type: "merchant"; key: string; row: SearchMerchantResult; globalIndex: number }
  | { type: "category"; key: string; row: SearchCategoryResult; globalIndex: number }
  | { type: "tag"; key: string; row: SearchTagResult; globalIndex: number }
  | { type: "account"; key: string; row: SearchAccountResult; globalIndex: number }
  | { type: "transaction"; key: string; row: SearchTransactionResult; globalIndex: number }
  | { type: "loan"; key: string; row: SearchLoanResult; globalIndex: number }
  | { type: "investment_transaction"; key: string; row: SearchInvestmentTransactionResult; globalIndex: number }
  | { type: "security"; key: string; row: SearchSecurityResult; globalIndex: number };

const GROUP_META: { type: FlatItem["type"]; label: string; icon: LucideIcon }[] = [
  { type: "merchant", label: "Merchants", icon: Store },
  { type: "category", label: "Categories", icon: Tags },
  { type: "tag", label: "Tags", icon: TagIcon },
  { type: "account", label: "Accounts", icon: Landmark },
  { type: "transaction", label: "Transactions", icon: ArrowLeftRight },
  { type: "loan", label: "Loans", icon: CreditCard },
  { type: "investment_transaction", label: "Investment Transactions", icon: TrendingUp },
  { type: "security", label: "Securities", icon: TrendingUp },
];

function buildFlat(data: SearchResults | undefined): FlatItem[] {
  if (!data) return [];
  const items: Omit<FlatItem, "globalIndex">[] = [
    ...data.merchants.map((row) => ({ type: "merchant" as const, key: `merchant-${row.id}`, row })),
    ...data.categories.map((row) => ({ type: "category" as const, key: `category-${row.id}`, row })),
    ...data.tags.map((row) => ({ type: "tag" as const, key: `tag-${row.id}`, row })),
    ...data.accounts.map((row) => ({ type: "account" as const, key: `account-${row.id}`, row })),
    ...data.transactions.map((row) => ({ type: "transaction" as const, key: `transaction-${row.id}`, row })),
    ...data.loans.map((row) => ({ type: "loan" as const, key: `loan-${row.id}`, row })),
    // Only a transaction whose security page we can actually link to.
    ...data.investment_transactions
      .filter((row) => row.security_id)
      .map((row) => ({ type: "investment_transaction" as const, key: `it-${row.id}`, row })),
    ...data.securities.map((row) => ({ type: "security" as const, key: `security-${row.id}`, row })),
  ];
  return items.map((item, globalIndex) => ({ ...item, globalIndex }) as FlatItem);
}

function hrefFor(item: FlatItem): string {
  switch (item.type) {
    case "merchant":    return `/merchants#id=${item.row.id}`;
    case "category":    return `/categories#id=${item.row.id}`;
    case "tag":         return `/tags#id=${item.row.id}`;
    case "account":     return `/accounts#id=${item.row.id}`;
    case "transaction": return `/transactions/${item.row.id}`;
    case "loan":        return `/loans/${item.row.id}`;
    case "investment_transaction":
      return `/market/${item.row.security_ticker ?? item.row.security_id}`;
    case "security":    return `/market/${item.row.ticker ?? item.row.id}`;
  }
}

function describe(item: FlatItem): { primary: string; secondary?: string; meta?: string } {
  switch (item.type) {
    case "merchant":
      return { primary: item.row.name, secondary: item.row.category_name ?? undefined };
    case "category":
      return { primary: item.row.name, secondary: item.row.parent_name ?? undefined };
    case "tag":
      return { primary: item.row.name };
    case "account":
      return { primary: item.row.name, secondary: item.row.account_type ?? undefined };
    case "transaction":
      return {
        primary: item.row.description ?? "—",
        secondary: item.row.merchant_name ?? item.row.category_name ?? undefined,
        meta: formatCurrency(item.row.amount),
      };
    case "loan":
      return { primary: item.row.name, secondary: item.row.lender ?? undefined };
    case "investment_transaction":
      return {
        primary: item.row.description ?? "—",
        secondary: item.row.security_ticker ?? undefined,
        meta: item.row.amount != null ? formatCurrency(item.row.amount) : undefined,
      };
    case "security":
      return { primary: item.row.ticker ?? item.row.name ?? "—", secondary: item.row.ticker ? (item.row.name ?? undefined) : undefined };
  }
}

export function CommandPalette({ open, onOpenChange }: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const [highlightedIndex, setHighlightedIndex] = useState(0);
  const debouncedQuery = useDebounced(query, 150);
  const trimmed = debouncedQuery.trim();

  const { data, isFetching } = useQuery({
    ...queries.search(trimmed),
    enabled: trimmed.length > 0,
    placeholderData: keepPreviousData,
  });

  const flat = useMemo(() => buildFlat(data), [data]);

  // Reset per-open-cycle state without an effect: clear the query when the
  // dialog transitions closed (adjust-state-during-render, same pattern as
  // TransactionDrawer's per-transaction reset).
  const [prevOpen, setPrevOpen] = useState(open);
  if (prevOpen !== open) {
    setPrevOpen(open);
    if (!open) {
      setQuery("");
      setHighlightedIndex(0);
    }
  }
  // Re-clamp the highlight whenever the result set itself changes.
  const [prevFlat, setPrevFlat] = useState(flat);
  if (prevFlat !== flat) {
    setPrevFlat(flat);
    setHighlightedIndex(0);
  }

  function select(item: FlatItem) {
    navigate(hrefFor(item));
    onOpenChange(false);
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (flat.length === 0) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setHighlightedIndex((i) => Math.min(i + 1, flat.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setHighlightedIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      const item = flat[highlightedIndex];
      if (item) select(item);
    }
  }

  return (
    <RadixDialog.Root open={open} onOpenChange={onOpenChange}>
      <RadixDialog.Portal>
        <RadixDialog.Overlay className="fixed inset-0 z-40 bg-black/40" />
        <RadixDialog.Content
          aria-describedby={undefined}
          className="fixed left-1/2 top-[12vh] z-50 w-full max-w-lg -translate-x-1/2 overflow-hidden rounded-xl border bg-card text-card-foreground shadow-xl focus:outline-none"
        >
          <RadixDialog.Title className="sr-only">Search</RadixDialog.Title>

          <div className="flex items-center gap-2 border-b px-4 py-3">
            <Search size={16} className="shrink-0 text-muted-foreground" />
            <input
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Search merchants, categories, transactions, accounts…"
              aria-label="Search"
              className="w-full bg-transparent text-sm placeholder:text-muted-foreground focus-visible:outline-none"
            />
            <kbd className="shrink-0 rounded border px-1.5 py-0.5 text-tiny text-muted-foreground">Esc</kbd>
          </div>

          <div className="max-h-[60vh] overflow-y-auto p-2">
            {trimmed.length === 0 ? (
              <p className="px-3 py-6 text-center text-sm text-muted-foreground">
                Search merchants, categories, tags, accounts, transactions, loans, and investments.
              </p>
            ) : flat.length > 0 ? (
              GROUP_META.map((g) => {
                const items = flat.filter((f) => f.type === g.type);
                if (items.length === 0) return null;
                const Icon = g.icon;
                return (
                  <div key={g.type} className="mb-1 last:mb-0">
                    <p className="px-2.5 py-1 text-caption font-medium uppercase tracking-wide text-muted-foreground">
                      {g.label}
                    </p>
                    {items.map((item) => {
                      const { primary, secondary, meta } = describe(item);
                      return (
                        <button
                          key={item.key}
                          onClick={() => select(item)}
                          onMouseEnter={() => setHighlightedIndex(item.globalIndex)}
                          className={cn(
                            "flex w-full items-center gap-2.5 rounded-lg px-2.5 py-2 text-left text-sm transition-colors focus-visible:outline-none",
                            item.globalIndex === highlightedIndex ? "bg-primary/8 text-primary" : "hover:bg-accent",
                          )}
                        >
                          <Icon size={14} className="shrink-0 text-muted-foreground" />
                          <span className="min-w-0 flex-1 truncate">
                            {primary}
                            {secondary && <span className="text-muted-foreground"> · {secondary}</span>}
                          </span>
                          {meta && <span className="shrink-0 font-mono tabular-nums text-muted-foreground">{meta}</span>}
                        </button>
                      );
                    })}
                  </div>
                );
              })
            ) : isFetching ? (
              <p className="px-3 py-6 text-center text-sm text-muted-foreground">Searching…</p>
            ) : (
              <p className="px-3 py-6 text-center text-sm text-muted-foreground">No results for &ldquo;{trimmed}&rdquo;</p>
            )}
          </div>
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  );
}
