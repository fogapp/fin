import { useEffect, useRef, useState, type ReactNode } from "react";
import { useMutation, useQueryClient, type QueryKey } from "@tanstack/react-query";
import { Check, Plus } from "lucide-react";
import { cn } from "@/lib/utils";
import { FieldError } from "@/components/ui/field";
import { invalidate } from "@/api/keys";

// ── Entity combobox ───────────────────────────────────────────────────────────
// The one search-or-create picker behind AccountCombobox, MerchantCombobox, and
// CategoryCombobox. Owns the interaction model those components used to
// duplicate verbatim: open/highlight state, capture-phase Escape, display-text
// sync, blur-vs-dropdown-click arbitration, and the optional Create row. The
// per-entity wrappers supply lookup, filtering, row rendering, and creation.

/** The create endpoints return the bare record, not the list row (no counts),
 *  so only the id and canonical name are read back from it. */
export interface CreatedEntity {
  id: string;
  name: string;
}

export interface EntityComboboxCreate {
  mutationFn: (name: string) => Promise<CreatedEntity>;
  /** Query cache to refresh so the created item shows up in future lists. */
  invalidateKey: QueryKey;
  /** Create-row label for the typed name, e.g. Create “Coffee”. */
  label: (name: string) => ReactNode;
}

interface Props<T> {
  value: string;
  onChange: (id: string) => void;
  items: T[];
  getId: (item: T) => string;
  /** Display text written into the input when the item is selected. */
  getLabel: (item: T) => string;
  /** Name compared against the query to suppress the Create row (label by default). */
  getMatchName?: (item: T) => string;
  filter: (item: T, query: string) => boolean;
  /** Row content rendered after the check icon. */
  renderOption: (item: T) => ReactNode;
  /**
   * Overrides the selected-item lookup, letting a wrapper resolve `value`
   * against a wider list than the one shown (e.g. hidden/excluded accounts).
   */
  selectedItem?: T | null;
  ariaLabel: string;
  placeholder: string;
  className?: string;
  inputClassName?: string;
  autoFocus?: boolean;
  onClose?: () => void;
  create?: EntityComboboxCreate;
  /** Adds a clear-selection row pinned to the top (CategoryCombobox's "No category"). */
  sentinelLabel?: ReactNode;
  /** Shown when nothing matches and no Create row applies. */
  emptyMessage?: string;
}

export function EntityCombobox<T>({
  value,
  onChange,
  items,
  getId,
  getLabel,
  getMatchName = getLabel,
  filter,
  renderOption,
  selectedItem,
  ariaLabel,
  placeholder,
  className,
  inputClassName,
  autoFocus,
  onClose,
  create: createConfig,
  sentinelLabel,
  emptyMessage,
}: Props<T>) {
  const qc = useQueryClient();
  // Tracks whether a mousedown is in progress inside the dropdown so blur
  // doesn't prematurely close the list before the click action fires.
  const dropdownMouseDown = useRef(false);

  const selected = selectedItem !== undefined ? selectedItem : items.find((it) => getId(it) === value) ?? null;
  const selectedLabel = selected ? getLabel(selected) : "";
  const [inputText, setInputText] = useState(selectedLabel);
  const [open, setOpen] = useState(false);
  const [highlightIdx, setHighlightIdx] = useState(0);
  const [error, setError] = useState("");

  // Capture-phase Escape: close the dropdown without letting an enclosing
  // dialog/drawer keyboard handler see the keypress and dismiss itself.
  useEffect(() => {
    if (!open) return;
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.stopImmediatePropagation();
        setOpen(false);
        setInputText(selectedLabel);
      }
    }
    window.addEventListener("keydown", onKeyDown, { capture: true });
    return () => window.removeEventListener("keydown", onKeyDown, { capture: true });
  }, [open, selectedLabel]);

  // Sync display text when the selection resolves to a different label.
  // Skip the update when value is set but the item isn't in the list yet
  // (e.g. just created — cache is still refreshing) so we don't clear the name
  // that onSuccess already wrote into inputText.
  // Adjust-state-during-render pattern instead of setState in an effect.
  const [prevSync, setPrevSync] = useState({ value, selectedLabel });
  if (prevSync.value !== value || prevSync.selectedLabel !== selectedLabel) {
    setPrevSync({ value, selectedLabel });
    if (!value) {
      setInputText("");
    } else if (selected) {
      setInputText(selectedLabel);
    }
  }

  const create = useMutation({
    mutationFn: (name: string) => {
      if (!createConfig) return Promise.reject(new Error("creation not enabled"));
      return createConfig.mutationFn(name);
    },
    onSuccess: (item) => {
      if (createConfig) invalidate(qc, createConfig.invalidateKey);
      onChange(item.id);
      // Set text before the cache refreshes so the render-sync doesn't clear it.
      setInputText(item.name);
      setOpen(false);
      setError("");
    },
    onError: (err: Error) => setError(err.message),
  });

  const query = inputText.trim().toLowerCase();
  const filtered = query ? items.filter((it) => filter(it, query)) : items;
  const exactMatch = items.some((it) => getMatchName(it).toLowerCase() === query);
  const showCreate = createConfig !== undefined && query.length > 0 && !exactMatch;
  const hasSentinel = sentinelLabel !== undefined;
  const offset = hasSentinel ? 1 : 0;
  const totalOptions = offset + filtered.length + (showCreate ? 1 : 0);

  function selectItem(item: T) {
    onChange(getId(item));
    setInputText(getLabel(item));
    setOpen(false);
    setError("");
  }

  function selectSentinel() {
    onChange("");
    setInputText("");
    setOpen(false);
    setError("");
  }

  function handleCreate() {
    const name = inputText.trim();
    if (name) create.mutate(name);
  }

  function handleInputChange(e: React.ChangeEvent<HTMLInputElement>) {
    setInputText(e.target.value);
    setOpen(true);
    setHighlightIdx(0);
    setError("");
    if (value && e.target.value !== selectedLabel) onChange("");
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (!open) {
      if (e.key === "ArrowDown" || e.key === "Enter") { setOpen(true); return; }
      return;
    }
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setHighlightIdx((i) => Math.min(i + 1, totalOptions - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setHighlightIdx((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (hasSentinel && highlightIdx === 0) selectSentinel();
      else if (highlightIdx - offset < filtered.length) selectItem(filtered[highlightIdx - offset]);
      else if (showCreate) handleCreate();
    } else if (e.key === "Escape") {
      setOpen(false);
      setInputText(selectedLabel);
    }
  }

  function handleBlur() {
    // If the user clicked inside the dropdown, the dropdownMouseDown ref will
    // be true — don't close yet, the click handler will fire next and reset it.
    if (dropdownMouseDown.current) return;
    setOpen(false);
    setInputText(selectedLabel);
    onClose?.();
  }

  return (
    <div className={cn("relative", className)}>
      <input
        value={inputText}
        onChange={handleInputChange}
        onFocus={() => setOpen(true)}
        onBlur={handleBlur}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        aria-label={ariaLabel}
        autoFocus={autoFocus}
        autoComplete="off"
        className={cn(
          inputClassName ?? "flex h-9 w-full rounded-lg border border-input bg-background px-3 py-1 text-sm shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:cursor-not-allowed disabled:opacity-50",
          error && "border-destructive"
        )}
      />

      <FieldError className="mt-1">{error}</FieldError>

      {open && (hasSentinel || totalOptions > 0) && (
        <ul
          className="absolute left-0 top-full z-50 mt-1 max-h-56 w-full overflow-auto rounded-lg border bg-card shadow-md"
          onMouseDown={() => { dropdownMouseDown.current = true; }}
          onMouseUp={() => { dropdownMouseDown.current = false; }}
        >
          {hasSentinel && (
            <li
              onMouseDown={selectSentinel}
              onMouseEnter={() => setHighlightIdx(0)}
              className={cn(
                "flex cursor-pointer items-center gap-2 px-3 py-2 text-sm text-muted-foreground",
                highlightIdx === 0 ? "bg-accent" : "hover:bg-accent/50"
              )}
            >
              <Check size={13} className={cn("shrink-0", !value ? "opacity-100" : "opacity-0")} />
              {sentinelLabel}
            </li>
          )}

          {filtered.map((item, i) => (
            <li
              key={getId(item)}
              onMouseDown={() => selectItem(item)}
              onMouseEnter={() => setHighlightIdx(i + offset)}
              className={cn(
                "flex cursor-pointer items-center gap-2 px-3 py-2 text-sm",
                i + offset === highlightIdx ? "bg-accent text-accent-foreground" : "text-foreground hover:bg-accent/50"
              )}
            >
              <Check size={13} className={cn("shrink-0", getId(item) === value ? "opacity-100" : "opacity-0")} />
              {renderOption(item)}
            </li>
          ))}

          {filtered.length === 0 && !showCreate && emptyMessage !== undefined && (
            <li className="px-3 py-2 text-sm text-muted-foreground">{emptyMessage}</li>
          )}

          {showCreate && (
            <li
              onMouseDown={handleCreate}
              onMouseEnter={() => setHighlightIdx(filtered.length + offset)}
              className={cn(
                "flex cursor-pointer items-center gap-2 border-t px-3 py-2 text-sm font-medium",
                highlightIdx === filtered.length + offset
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:bg-accent/50"
              )}
            >
              <Plus size={13} className="shrink-0" />
              {create.isPending ? "Creating…" : createConfig?.label(inputText.trim())}
            </li>
          )}
        </ul>
      )}
    </div>
  );
}
