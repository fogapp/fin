import { ArrowDown, ArrowUp } from "lucide-react";
import { cn } from "@/lib/utils";
import type { StatDirection } from "@/api/types";

/**
 * The one change-delta presentation for the Stats system (index cards +
 * detail hero): arrow-in-circle + signed percentage, colored by whether the
 * move is good (`direction`), not by its raw sign. Neutral stats render the
 * arrow muted — a change in transaction count is information, not judgment.
 */
export function ChangeBadge({ change, direction, size = "sm", suffix }: {
  change: number | null | undefined;
  direction: StatDirection;
  size?: "sm" | "md";
  /** Muted annotation after the number (e.g. "projected"). */
  suffix?: string;
}) {
  if (change == null) return null;

  const up = change >= 0;
  const good = direction === "neutral" ? null : (direction === "up_good") === up;
  const colorText = good == null ? "text-muted-foreground" : good ? "text-positive" : "text-negative";
  const colorBg = good == null ? "bg-muted-foreground" : good ? "bg-positive" : "bg-negative";

  return (
    <span className={cn("inline-flex items-center gap-1.5 font-semibold", colorText, size === "sm" ? "text-xs" : "text-base")}>
      <span className={cn(
        "flex shrink-0 items-center justify-center rounded-full text-white",
        colorBg,
        size === "sm" ? "h-4 w-4" : "h-5 w-5",
      )}>
        {up
          ? <ArrowUp size={size === "sm" ? 9 : 11} strokeWidth={2.5} />
          : <ArrowDown size={size === "sm" ? 9 : 11} strokeWidth={2.5} />}
      </span>
      <span className="tabular-nums">
        {up ? "+" : ""}{change.toFixed(1)}%
        {suffix && <span className="ml-1 font-normal text-muted-foreground">{suffix}</span>}
      </span>
    </span>
  );
}
