import { useState } from "react";
import { BookMarked, Check, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

/**
 * The bookmark button that saves the current state under a name and lists the
 * saved ones to reapply or delete — the transaction table's saved views and
 * the cashflow page's saved reports. Callers own what "current state" means:
 * `onSave(name)` persists it (resolving once saved, which closes the panel)
 * and `onApply(item)` restores it.
 */
export function SavedItemsMenu<T extends { id: string; name: string }>({
  noun,
  saveLabel,
  items,
  activeId = null,
  saving = false,
  onSave,
  onApply,
  onDelete,
  className,
}: {
  /** Lower-case singular, e.g. "view" → "Saved views", "View name", "Delete view". */
  noun: string;
  /** Heading over the name field, e.g. "Save current as view". */
  saveLabel: string;
  items: T[];
  /** Marks the applied item and tints the button. */
  activeId?: string | null;
  saving?: boolean;
  onSave: (name: string) => Promise<unknown>;
  onApply: (item: T) => void;
  onDelete: (item: T) => void;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const Noun = noun.charAt(0).toUpperCase() + noun.slice(1);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    try {
      await onSave(trimmed);
    } catch {
      return; // keep the panel and the typed name so the save can be retried
    }
    setName("");
    setOpen(false);
  }

  return (
    <Popover open={open} onOpenChange={(next) => { setOpen(next); if (next) setName(""); }}>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="icon-sm"
          className={cn(
            activeId
              ? "text-primary hover:bg-primary/10 hover:text-primary"
              : "text-muted-foreground hover:text-foreground",
            className,
          )}
          title={`Saved ${noun}s`}
          aria-label={`Saved ${noun}s`}
        >
          <BookMarked size={13} />
        </Button>
      </PopoverTrigger>

      <PopoverContent className="w-60 p-0" aria-label={`Saved ${noun}s`}>
        <div className="border-b p-2">
          <p className="mb-1.5 text-caption font-medium text-muted-foreground">{saveLabel}</p>
          <form onSubmit={submit} className="flex gap-1.5">
            <Input
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={`${Noun} name…`}
              aria-label={`${Noun} name`}
              className="h-7 flex-1 min-w-0 px-2 text-xs"
            />
            <Button type="submit" size="xs" disabled={!name.trim() || saving}>
              Save
            </Button>
          </form>
        </div>

        {items.length > 0 ? (
          <ul className="py-1">
            {items.map((item) => (
              <li key={item.id} className="group flex items-center gap-1 px-1">
                <button
                  onClick={() => { onApply(item); setOpen(false); }}
                  className={cn(
                    "flex flex-1 items-center gap-2 rounded px-2 py-1.5 text-sm transition-colors hover:bg-accent min-w-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                    activeId === item.id && "font-medium text-primary",
                  )}
                >
                  <Check size={12} className={cn("shrink-0", activeId === item.id ? "opacity-100" : "opacity-0")} />
                  <span className="truncate">{item.name}</span>
                </button>
                <button
                  onClick={() => onDelete(item)}
                  className="shrink-0 rounded p-1 text-muted-foreground opacity-0 transition-opacity hover:text-destructive focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary group-hover:opacity-100"
                  title={`Delete ${noun}`}
                  aria-label={`Delete ${noun} ${item.name}`}
                >
                  <Trash2 size={12} />
                </button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="px-3 py-2 text-xs text-muted-foreground">No saved {noun}s yet</p>
        )}
      </PopoverContent>
    </Popover>
  );
}
