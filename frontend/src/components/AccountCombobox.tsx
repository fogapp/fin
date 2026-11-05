import { api } from "@/api/client";
import { Badge } from "@/components/ui/badge";
import { EntityCombobox } from "@/components/EntityCombobox";
import type { Account } from "@/api/types";
import { keys } from "@/api/keys";

// ── Account combobox ──────────────────────────────────────────────────────────
// Search-or-create picker for accounts; the interaction model lives in
// EntityCombobox. "Create" makes an *external* account — a lightweight
// stand-in for an account we don't sync (e.g. "Schwab") used as a transfer
// counterparty.

interface Props {
  value: string;
  onChange: (accountId: string) => void;
  accounts: Account[];
  /** Accounts to hide from the list (e.g. the transaction's own account). */
  excludeIds?: string[];
  placeholder?: string;
  className?: string;
  autoFocus?: boolean;
  /** Offer "Create external account" for unmatched queries (default true). */
  allowCreate?: boolean;
  /** Extra fields merged into the create-account request (e.g. account_type). */
  createDefaults?: Record<string, string>;
}

export function AccountCombobox({ value, onChange, accounts, excludeIds = [], placeholder = "Search or create account…", className, autoFocus, allowCreate = true, createDefaults }: Props) {
  const visible = accounts.filter((a) => !a.hidden && !excludeIds.includes(a.id));

  return (
    <EntityCombobox
      value={value}
      onChange={onChange}
      items={visible}
      getId={(a) => a.id}
      getLabel={(a) => a.name}
      filter={(a, query) =>
        a.name.toLowerCase().includes(query) ||
        (a.broker_name ?? "").toLowerCase().includes(query) ||
        // Search by account number — typically the last four digits. External
        // accounts carry an auto-generated "ext-…" number, which isn't
        // something users know; skip it so digits never match those.
        (a.kind !== "external" && (a.account_number ?? "").toLowerCase().includes(query))}
      renderOption={(a) => (
        <>
          <span className="min-w-0 flex-1 truncate">{a.name}</span>
          {a.kind === "external" ? (
            <Badge variant="outline" className="shrink-0">External</Badge>
          ) : (
            <span className="flex shrink-0 items-center gap-1.5 text-xs text-muted-foreground">
              {a.broker_name}
              {a.account_number && (
                <span className="font-mono">····{a.account_number.slice(-4)}</span>
              )}
            </span>
          )}
        </>
      )}
      // Resolve against the full list so a hidden/excluded selection keeps its name.
      selectedItem={accounts.find((a) => a.id === value) ?? null}
      ariaLabel="Account"
      placeholder={placeholder}
      className={className}
      autoFocus={autoFocus}
      create={allowCreate ? {
        mutationFn: (name) => api.post<Account>("/accounts", { name, kind: "external", ...createDefaults }),
        invalidateKey: keys.accounts,
        label: (name) => <>Create external account &ldquo;{name}&rdquo;</>,
      } : undefined}
    />
  );
}
