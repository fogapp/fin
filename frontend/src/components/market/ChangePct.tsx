import { cn } from "@/lib/utils";

/** Signed, colored percent — the app-wide rendering for price changes. */
export function ChangePct({ value, className }: { value: number | null | undefined; className?: string }) {
  if (value == null) return <span className={cn("text-muted-foreground", className)}>—</span>;
  return (
    <span className={cn("tabular-nums", value > 0 ? "text-positive" : value < 0 ? "text-negative" : "text-muted-foreground", className)}>
      {value > 0 ? "+" : ""}{value.toFixed(2)}%
    </span>
  );
}
