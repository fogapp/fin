import { useState, useEffect } from "react";
import { cn } from "@/lib/utils";
import { Input } from "@/components/ui/input";

interface Props {
  value: string;
  onCommit: (v: string) => void;
  type?: string;
  placeholder?: string;
  className?: string;
  debounceMs?: number;
  /** Accessible name — pass when the input has no visible label. */
  "aria-label"?: string;
}

export function DeferredInput({ value, onCommit, type = "text", placeholder, className, debounceMs = 600, "aria-label": ariaLabel }: Props) {
  const [local, setLocal] = useState(value);

  // Re-sync the draft when the committed value changes from outside
  // (adjust-state-during-render pattern instead of setState in an effect).
  const [prevValue, setPrevValue] = useState(value);
  if (prevValue !== value) {
    setPrevValue(value);
    setLocal(value);
  }

  useEffect(() => {
    if (local === value) return;
    const timer = setTimeout(() => onCommit(local), debounceMs);
    return () => clearTimeout(timer);
  }, [local]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Input
      type={type}
      value={local}
      onChange={(e) => setLocal(e.target.value)}
      onBlur={() => { if (local !== value) onCommit(local); }}
      onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }}
      placeholder={placeholder}
      aria-label={ariaLabel ?? placeholder}
      className={cn("flex-1", type === "number" && "tabular-nums", className)}
    />
  );
}
