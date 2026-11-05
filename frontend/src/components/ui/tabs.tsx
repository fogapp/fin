import { cn } from "@/lib/utils";

// ── Tabs / segmented control ──────────────────────────────────────────────────
// The app's one active-state language for tab-like switchers: primary-tinted
// pill on the active item, muted text elsewhere. Use for horizontal tab rows,
// timeframe pickers, and filter segments; use layout/SectionRailNav for the
// vertical section rails.

export interface TabOption<T extends string = string> {
  value: T;
  /** Usually a string; icon-only tabs pass a node with an aria-label. */
  label: React.ReactNode;
  count?: number;
}

export function Tabs<T extends string>({ value, onChange, options, size = "md", className, "aria-label": ariaLabel }: {
  value: T;
  onChange: (value: T) => void;
  options: TabOption<T>[];
  size?: "sm" | "md";
  className?: string;
  "aria-label"?: string;
}) {
  return (
    <div role="tablist" aria-label={ariaLabel} className={cn("flex items-center gap-1", className)}>
      {options.map((o) => (
        <button
          key={o.value}
          role="tab"
          aria-selected={value === o.value}
          onClick={() => onChange(o.value)}
          className={cn(
            "rounded-lg font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
            { sm: "px-2.5 py-1 text-xs", md: "px-3 py-1.5 text-sm" }[size],
            value === o.value
              ? "bg-primary/10 text-primary"
              : "text-muted-foreground hover:bg-accent hover:text-foreground",
          )}
        >
          {o.label}
          {o.count != null && <span className="ml-1.5 text-xs opacity-70">{o.count}</span>}
        </button>
      ))}
    </div>
  );
}
