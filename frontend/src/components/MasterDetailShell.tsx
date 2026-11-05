import { useState, Fragment, type ReactNode } from "react";
import { ChevronLeft, Plus, X, type LucideIcon } from "lucide-react";
import { useHashParam } from "@/hooks/useHashParam";
import { useListSearch } from "@/hooks/useListSearch";
import { SearchInput } from "@/components/SearchInput";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { PageHeader } from "@/components/layout/PageHeader";

// ── Master-detail shell ───────────────────────────────────────────────────────
// The two-pane list/detail layout shared by Accounts, Categories, Tags, and Merchants:
// hash-param selection, searchable list with keyboard navigation, the add/close
// toggle with an inline create form, responsive pane switching, and the mobile
// back bar. Pages supply the detail body, the create form (usually an
// InlineCreateForm), and custom rows or list bodies where the default row
// doesn't fit.

export interface MasterDetailListContext<T> {
  filtered: T[];
  highlightedIndex: number | null;
  isSearching: boolean;
  selectedId: string | null;
  setSelectedId: (id: string | null) => void;
  /** Row click behavior: selects, or clears when the row is already selected. */
  toggleSelected: (id: string) => void;
  openNew: () => void;
}

interface Props<T extends { id: string; name: string }> {
  /** Plural page title, also the mobile back-bar label ("Tags"). */
  title: string;
  /** Singular noun for the new-item button and the select prompt ("tag"). */
  noun: string;
  /** Lower-case plural for list empty/error copy ("tags"). */
  nounPlural: string;
  icon: LucideIcon;
  items: T[];
  isLoading: boolean;
  isError: boolean;
  refetch: () => void;
  renderNewForm: (props: { onCreated: (id: string) => void; onCancel: () => void }) => ReactNode;
  /** Flat-list row renderer; the shell supplies keys and empty states.
   *  Defaults to a MasterDetailRow showing the name and `rowCount`. */
  renderRow?: (item: T, props: { selected: boolean; highlighted: boolean; onClick: () => void }) => ReactNode;
  /** Trailing count on the default row (e.g. transactions per tag). */
  rowCount?: (item: T) => number | null | undefined;
  /** Full custom list body (e.g. Categories' tree); wins over renderRow. */
  renderListBody?: (ctx: MasterDetailListContext<T>) => ReactNode;
  renderDetail: (id: string, setSelectedId: (id: string | null) => void) => ReactNode;
}

export function MasterDetailShell<T extends { id: string; name: string }>({
  title,
  noun,
  nounPlural,
  icon: Icon,
  items,
  isLoading,
  isError,
  refetch,
  renderNewForm,
  renderRow,
  rowCount,
  renderListBody,
  renderDetail,
}: Props<T>) {
  const [rawId, setHashId] = useHashParam("id");
  const selectedId = rawId ?? null;
  const setSelectedId = (id: string | null) => setHashId(id);
  const [showNew, setShowNew] = useState(false);

  const { search, filtered, highlightedIndex, inputRef, handleChange, handleKeyDown } =
    useListSearch(items);
  const isSearching = search.trim().length > 0;

  const ctx: MasterDetailListContext<T> = {
    filtered,
    highlightedIndex,
    isSearching,
    selectedId,
    setSelectedId,
    toggleSelected: (id) => setSelectedId(id === selectedId ? null : id),
    openNew: () => setShowNew(true),
  };

  const row = renderRow ?? ((item: T, rowProps: { selected: boolean; highlighted: boolean; onClick: () => void }) => (
    <MasterDetailRow name={item.name} count={rowCount?.(item)} {...rowProps} />
  ));

  const listBody = renderListBody ? renderListBody(ctx) : (
    <>
      {filtered.map((item, i) => (
        <Fragment key={item.id}>
          {row(item, {
            selected: item.id === selectedId,
            highlighted: i === highlightedIndex,
            onClick: () => ctx.toggleSelected(item.id),
          })}
        </Fragment>
      ))}
      {filtered.length === 0 && (
        isSearching ? (
          <EmptyState title={`No ${nounPlural} match the current filters.`} />
        ) : (
          <EmptyState
            icon={Icon}
            title={`No ${nounPlural} yet.`}
            action={<Button size="sm" onClick={ctx.openNew}>New {noun}</Button>}
          />
        )
      )}
    </>
  );

  return (
    <div className="flex h-full">
      {/* List */}
      <div className={`flex-col border-r ${selectedId ? "hidden md:flex md:w-72" : "flex w-full md:w-72"}`}>
        <div className="flex h-14 items-center gap-2 border-b px-4">
          <SearchInput
            ref={inputRef}
            value={search}
            onChange={handleChange}
            onKeyDown={(e) => handleKeyDown(e, (item) => setSelectedId(item.id))}
            placeholder={`Search ${nounPlural}…`}
          />
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => setShowNew((v) => !v)}
            className="shrink-0 text-muted-foreground hover:text-foreground"
            title={`New ${noun}`}
            aria-label={`New ${noun}`}
          >
            {showNew ? <X size={15} /> : <Plus size={15} />}
          </Button>
        </div>

        {showNew && renderNewForm({
          onCreated: (id) => { setSelectedId(id); setShowNew(false); },
          onCancel: () => setShowNew(false),
        })}

        <div className="flex-1 overflow-y-auto">
          {isLoading ? (
            <ListSkeleton />
          ) : isError ? (
            <ErrorState title={`Failed to load ${nounPlural}`} onRetry={() => refetch()} />
          ) : (
            listBody
          )}
        </div>
      </div>

      {/* Detail */}
      <div className={`flex-col overflow-y-auto ${selectedId ? "flex flex-1" : "hidden md:flex md:flex-1"}`}>
        {selectedId ? (
          <>
            <button
              onClick={() => setSelectedId(null)}
              className="flex h-11 items-center gap-1.5 border-b px-3 text-sm text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary md:hidden"
            >
              <ChevronLeft size={16} />
              {title}
            </button>
            {renderDetail(selectedId, setSelectedId)}
          </>
        ) : (
          <>
            <PageHeader title={title} level={1} />
            <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
              <div className="space-y-2 text-center">
                <Icon size={28} className="mx-auto opacity-30" />
                <p>Select {/^[aeiou]/i.test(noun) ? "an" : "a"} {noun} to see details</p>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

/** The standard list row: name on the left, an optional count on the right. */
export function MasterDetailRow({ name, count, selected, highlighted = false, onClick }: {
  name: string;
  count?: number | null;
  selected: boolean;
  highlighted?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex w-full items-center justify-between px-4 py-3 text-left text-sm transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary
        ${selected ? "bg-primary/8 text-primary" : ""}
        ${highlighted && !selected ? "bg-accent" : ""}`}
    >
      <span className="truncate font-medium">{name}</span>
      {count != null && <span className="ml-2 shrink-0 text-xs text-muted-foreground">{count}</span>}
    </button>
  );
}

function ListSkeleton() {
  return (
    <div className="space-y-px p-2">
      {Array.from({ length: 12 }).map((_, i) => (
        <Skeleton key={i} className="h-12 rounded-lg" />
      ))}
    </div>
  );
}

/** Structure-matched loading state for the Tags/Merchants-style detail pane. */
export function MasterDetailLoading() {
  return (
    <div className="space-y-6 p-6">
      <Skeleton className="h-6 w-32" />
      <Skeleton className="h-4 w-48" />
      <Skeleton className="h-40 rounded-xl" />
      <div className="grid gap-6 lg:grid-cols-[1fr_240px]">
        <Skeleton className="h-64 rounded-xl" />
        <div className="space-y-4">
          <Skeleton className="h-48 rounded-xl" />
          <Skeleton className="h-32 rounded-xl" />
        </div>
      </div>
    </div>
  );
}
