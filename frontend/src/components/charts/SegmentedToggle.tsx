import { cn } from "@/lib/utils";

// Same visual language as TimeframeSelector — a compact segmented group sized
// for a page subheader (e.g. Common/Outlier/Both) and for a chart card's own
// header (e.g. a split/scale pair).
export function SegmentedToggle<T extends string>({ label, options, value, onChange }: {
  label: string;
  options: readonly { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
}) {
  return (
    <div role="group" aria-label={label} className="inline-flex items-center rounded-lg border bg-muted/40 p-0.5">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          aria-pressed={value === o.value}
          onClick={() => onChange(o.value)}
          className={cn(
            "rounded-md px-2 py-0.5 text-caption font-medium leading-4 transition-colors",
            value === o.value
              ? "bg-primary/10 text-primary"
              : "text-muted-foreground hover:bg-accent hover:text-foreground",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
