import { Link } from "react-router-dom";
import { TrendingUp, TrendingDown, Minus } from "lucide-react";
import { cn, moneyColor } from "@/lib/utils";

export interface StatItem {
  label: string;
  value: string;
  change?: number | null;
  invertColor?: boolean;
  highlight?: "positive" | "negative";
  /** Insert a taller divider before this item */
  dividerBefore?: boolean;
  /** Link the stat through to a detail page (e.g. /stats/monthly_spend) */
  href?: string;
}

interface Props {
  stats: StatItem[];
  /** Apply -mx-6 to bleed to the edges of a p-6 container */
  flush?: boolean;
  /** Show top border (default true) */
  borderTop?: boolean;
}

export function StatRibbon({ stats, flush = false, borderTop = true }: Props) {
  return (
    <div className={cn(
      "flex items-stretch gap-x-1 overflow-x-auto border-b bg-card px-4 scrollbar-none",
      borderTop && "border-t",
      flush && "-mx-6",
    )}>
      {stats.map((stat, i) => (
        <span key={i} className="flex shrink-0 items-center">
          {i > 0 && !stat.dividerBefore && (
            <span className="text-border select-none">·</span>
          )}
          {stat.dividerBefore && i > 0 && (
            <span className="mx-3 h-4 w-px bg-border" />
          )}
          {stat.href ? (
            <Link
              to={stat.href}
              className="rounded-md transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <RibbonStat {...stat} />
            </Link>
          ) : (
            <RibbonStat {...stat} />
          )}
        </span>
      ))}
    </div>
  );
}

function RibbonStat({ label, value, change, invertColor = false, highlight }: StatItem) {
  const isPositive = change != null && (invertColor ? change < 0 : change > 0);
  const isNegative = change != null && (invertColor ? change > 0 : change < 0);
  // Map the highlight prop onto the shared money-color helper (keeps the API).
  const valueColor = moneyColor(highlight === "positive" ? 1 : highlight === "negative" ? -1 : 0);

  return (
    <span className="flex shrink-0 flex-col px-3 py-2.5">
      <span className="flex items-center gap-1">
        <span className={cn("text-sm font-semibold tabular-nums leading-tight", valueColor)}>{value}</span>
        {change != null && (
          <span className={cn(
            "flex items-center gap-0.5 text-tiny font-medium",
            isPositive ? "text-positive" : isNegative ? "text-negative" : "text-muted-foreground",
          )}>
            {isPositive ? <TrendingUp size={10} /> : isNegative ? <TrendingDown size={10} /> : <Minus size={10} />}
            {(change >= 0 ? "+" : "") + change.toFixed(1)}%
          </span>
        )}
      </span>
      <span className="text-tiny text-muted-foreground leading-tight">{label}</span>
    </span>
  );
}
