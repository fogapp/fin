import { useRef, useState } from "react";
import { cn } from "@/lib/utils";
import { Input } from "@/components/ui/input";

/**
 * A dollar amount that saves on blur or Enter (Escape reverts). Shows the
 * current value until focused, so it never fights a refetch. An empty field
 * commits null when `allowEmpty` — "no amount" rather than zero.
 */
export function AmountInput({ value, onCommit, label, placeholder, allowEmpty = false, autoFocus, className }: {
  value: number | null;
  onCommit: (value: number | null) => void;
  label: string;
  placeholder?: string;
  allowEmpty?: boolean;
  autoFocus?: boolean;
  className?: string;
}) {
  const [draft, setDraft] = useState<string | null>(null);
  const cancelled = useRef(false);
  const shown = draft ?? (value == null ? "" : String(value));

  function commit() {
    if (draft == null || cancelled.current) {
      cancelled.current = false;
      setDraft(null);
      return;
    }
    const trimmed = draft.trim().replace(/[$,]/g, "");
    setDraft(null);
    if (trimmed === "") {
      if (allowEmpty && value != null) onCommit(null);
      return;
    }
    const n = Number(trimmed);
    if (Number.isNaN(n) || n < 0 || n === value) return;
    onCommit(Math.round(n * 100) / 100);
  }

  return (
    <div className={cn("relative", className)}>
      <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">$</span>
      <Input
        inputMode="decimal"
        autoFocus={autoFocus}
        aria-label={label}
        placeholder={placeholder}
        value={shown}
        onFocus={() => setDraft(shown)}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === "Enter") e.currentTarget.blur();
          else if (e.key === "Escape") {
            cancelled.current = true;
            e.currentTarget.blur();
          }
        }}
        className="h-8 pl-5 pr-2 text-right text-sm tabular-nums"
      />
    </div>
  );
}
