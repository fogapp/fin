import { useQuery } from "@tanstack/react-query";
import { ChevronDown } from "lucide-react";
import { queries } from "@/api/queries";
import { Select } from "@/components/ui/select";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";

/** Page-level account/tag scoping shared by the cashflow analysis sections. */
export interface CashflowScopeState {
  accountId?: string;
  tagId?: string;
  /** Rows carrying any of these tags drop out of every number (e.g. leave
   *  vacation spending out of the analysis). A view filter only — the
   *  transactions themselves are untouched. */
  excludeTagIds?: string[];
}

// Compact account + tag selects for the section subheaders. Empty value means
// "everything" — the backend only scopes when the params are present.
export function ScopeFilter({ value, onChange }: {
  value: CashflowScopeState;
  onChange: (next: CashflowScopeState) => void;
}) {
  const { data: accounts } = useQuery(queries.accounts());
  const { data: tags } = useQuery(queries.tags());

  const visibleAccounts = (accounts ?? []).filter((a) => !a.hidden && a.cash_transaction_count > 0);
  // Ignore ids of tags deleted since the scope was stored.
  const excluded = new Set(value.excludeTagIds ?? []);
  const excludedTags = (tags ?? []).filter((t) => excluded.has(t.id));

  const toggleExcluded = (tagId: string, checked: boolean) => {
    const next = new Set(excluded);
    if (checked) next.add(tagId);
    else next.delete(tagId);
    onChange({ ...value, excludeTagIds: next.size ? [...next] : undefined });
  };

  return (
    <div className="flex items-center gap-1.5">
      <Select
        aria-label="Account filter"
        className="h-7 rounded-md py-0 pl-2 pr-7 text-caption font-medium"
        wrapperClassName="w-32"
        value={value.accountId ?? ""}
        onChange={(e) => onChange({ ...value, accountId: e.target.value || undefined })}
      >
        <option value="">All accounts</option>
        {visibleAccounts.map((a) => (
          <option key={a.id} value={a.id}>{a.name}</option>
        ))}
      </Select>
      {(tags?.length ?? 0) > 0 && (
        <>
          <Select
            aria-label="Tag filter"
            className="h-7 rounded-md py-0 pl-2 pr-7 text-caption font-medium"
            wrapperClassName="w-28"
            value={value.tagId ?? ""}
            onChange={(e) => onChange({ ...value, tagId: e.target.value || undefined })}
          >
            <option value="">All tags</option>
            {(tags ?? []).map((t) => (
              <option key={t.id} value={t.id}>{t.name}</option>
            ))}
          </Select>
          <DropdownMenu modal={false}>
            <DropdownMenuTrigger
              aria-label="Exclude tags"
              className={cn(
                "flex h-7 max-w-36 items-center gap-1 rounded-md border border-input bg-background pl-2 pr-1.5 text-caption font-medium shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                excludedTags.length > 0 && "border-primary text-primary",
              )}
            >
              <span className="truncate">
                {excludedTags.length === 0
                  ? "Exclude tags"
                  : excludedTags.length === 1
                    ? `Excl. ${excludedTags[0].name}`
                    : `Excl. ${excludedTags.length} tags`}
              </span>
              <ChevronDown size={13} className="shrink-0 text-muted-foreground" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="max-h-80 overflow-y-auto">
              <DropdownMenuLabel>Leave out transactions tagged</DropdownMenuLabel>
              {(tags ?? []).map((t) => (
                <DropdownMenuCheckboxItem
                  key={t.id}
                  checked={excluded.has(t.id)}
                  onCheckedChange={(checked) => toggleExcluded(t.id, checked === true)}
                >
                  {t.name}
                </DropdownMenuCheckboxItem>
              ))}
              {excludedTags.length > 0 && (
                <>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onSelect={() => onChange({ ...value, excludeTagIds: undefined })}>
                    Clear exclusions
                  </DropdownMenuItem>
                </>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </>
      )}
    </div>
  );
}
