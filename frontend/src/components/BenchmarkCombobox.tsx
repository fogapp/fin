import { useEffect, useRef, useState } from "react";
import { X, Plus } from "lucide-react";
import { cn } from "@/lib/utils";
import type { BenchmarkMeta } from "@/api/types";

interface Props {
  selected: string[];
  onAdd: (symbol: string) => void;
  onRemove: (symbol: string) => void;
  suggestions: BenchmarkMeta[];
  colors: Record<string, string>;
}

export function BenchmarkCombobox({ selected, onAdd, onRemove, suggestions, colors }: Props) {
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const dropdownMouseDown = useRef(false);

  const normalised = query.trim().toUpperCase();

  const filtered = suggestions.filter(
    (s) =>
      !selected.includes(s.symbol) &&
      (s.symbol.includes(normalised) || s.label.toUpperCase().includes(normalised))
  );

  const canAddCustom =
    normalised.length > 0 &&
    normalised.length <= 10 &&
    !selected.includes(normalised) &&
    !suggestions.some((s) => s.symbol === normalised);

  const options = [
    ...filtered,
    ...(canAddCustom ? [{ symbol: normalised, label: normalised }] : []),
  ];

  function add(symbol: string) {
    onAdd(symbol.toUpperCase());
    setQuery("");
    setOpen(false);
    inputRef.current?.focus();
  }

  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") { e.stopImmediatePropagation(); setOpen(false); setQuery(""); }
      if (e.key === "Enter" && options.length > 0) { e.preventDefault(); add(options[0].symbol); }
    }
    window.addEventListener("keydown", onKey, { capture: true });
    return () => window.removeEventListener("keydown", onKey, { capture: true });
  }, [open, options]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="relative flex flex-wrap items-center gap-1">
      {/* Selected chips */}
      {selected.map((symbol) => (
        <span
          key={symbol}
          style={{ borderColor: colors[symbol], color: colors[symbol] }}
          className="flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium"
        >
          {symbol}
          <button
            onClick={() => onRemove(symbol)}
            className="rounded-full opacity-60 hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            aria-label={`Remove ${symbol}`}
          >
            <X size={10} />
          </button>
        </span>
      ))}

      {/* Input trigger */}
      <div className="relative">
        <div
          className="flex cursor-text items-center gap-1 rounded-full border border-input px-2.5 py-0.5 text-xs text-muted-foreground hover:border-foreground/40 transition-colors"
          onClick={() => { setOpen(true); inputRef.current?.focus(); }}
        >
          <Plus size={10} />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => { setQuery(e.target.value); setOpen(true); }}
            onFocus={() => setOpen(true)}
            onBlur={() => { if (!dropdownMouseDown.current) { setOpen(false); setQuery(""); } }}
            placeholder="Compare…"
            aria-label="Add benchmark to compare"
            className="w-20 bg-transparent outline-none placeholder:text-muted-foreground"
          />
        </div>

        {open && options.length > 0 && (
          <div
            className="absolute left-0 top-full z-50 mt-1 min-w-40 rounded-lg border bg-card shadow-md"
            onMouseDown={() => { dropdownMouseDown.current = true; }}
            onMouseUp={() => { dropdownMouseDown.current = false; }}
          >
            {options.map((opt) => {
              const isCustom = !suggestions.some((s) => s.symbol === opt.symbol);
              return (
                <button
                  key={opt.symbol}
                  onClick={() => add(opt.symbol)}
                  className={cn(
                    "flex w-full items-center gap-2 px-3 py-2 text-left text-xs hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
                    "first:rounded-t-lg last:rounded-b-lg"
                  )}
                >
                  <span className="font-mono font-semibold">{opt.symbol}</span>
                  {isCustom
                    ? <span className="text-muted-foreground">add ticker</span>
                    : <span className="text-muted-foreground">{opt.label}</span>
                  }
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
