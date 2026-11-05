/**
 * The one timeframe control: a compact segmented group sized for a chart
 * card or page header — chart chrome, not a form control. One instance per
 * page (in the primary chart card of whatever is visible, or the subheader)
 * scopes every chart and stat below it; state comes from the page's single
 * useTimeframe.
 *
 * Pass `timeframe` (the whole useTimeframe object) to offer a Custom segment
 * that opens a from/to date panel, and to render the timeframe's own options;
 * pass just value/onChange for the default presets only.
 */
import { useState } from "react";
import { cn, formatDate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { BUILTIN_TIMEFRAME_KEYS, builtinOption, TIMEFRAME_PRESETS, type BuiltinTimeframe, type Timeframe, type TimeframeOption } from "./timeframe";

export function TimeframeSelector({ value, onChange, presets, options: optionsProp, className, timeframe }: {
  value: string;
  onChange: (key: string) => void;
  /** Subset of built-in presets to offer, shown in catalog order (default: the five in TIMEFRAME_PRESETS). */
  presets?: BuiltinTimeframe[];
  /** Explicit buttons; overrides `presets` and the timeframe's own options. */
  options?: TimeframeOption[];
  className?: string;
  /** When given, a "Custom" segment opens an explicit from/to panel. */
  timeframe?: Timeframe;
}) {
  const options: TimeframeOption[] =
    optionsProp
    ?? (presets && BUILTIN_TIMEFRAME_KEYS.filter((k) => presets.includes(k)).map((k) => builtinOption(k)))
    ?? timeframe?.options
    ?? TIMEFRAME_PRESETS.map((p) => builtinOption(p.key));
  const [panelOpen, setPanelOpen] = useState(false);
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  function openPanel() {
    setFrom(timeframe?.customRange?.from ?? timeframe?.from ?? "");
    setTo(timeframe?.customRange?.to ?? timeframe?.to ?? "");
    setPanelOpen(true);
  }

  function apply() {
    if (!timeframe || !from || !to) return;
    // Swapped bounds are corrected rather than rejected.
    const [lo, hi] = from <= to ? [from, to] : [to, from];
    timeframe.setCustom({ from: lo, to: hi });
    setPanelOpen(false);
  }

  return (
    <Popover open={panelOpen} onOpenChange={(open) => (open ? openPanel() : setPanelOpen(false))}>
      <PopoverAnchor asChild>
        <div className={cn("relative inline-flex", className)}>
          <div
            role="group"
            aria-label="Timeframe"
            className="inline-flex items-center rounded-lg border bg-muted/40 p-0.5"
          >
            {options.map((p) => (
              <button
                key={p.key}
                type="button"
                aria-pressed={value === p.key}
                title={rangeTitle(p)}
                onClick={() => { setPanelOpen(false); onChange(p.key); }}
                className={cn(
                  "rounded-md px-2 py-0.5 text-caption font-medium leading-4 transition-colors",
                  value === p.key
                    ? "bg-primary/10 text-primary"
                    : "text-muted-foreground hover:bg-accent hover:text-foreground",
                )}
              >
                {p.label}
              </button>
            ))}
            {timeframe && (
              <PopoverTrigger asChild>
                <button
                  type="button"
                  aria-pressed={value === "custom"}
                  title={value === "custom" && timeframe.customRange
                    ? `${timeframe.customRange.from} → ${timeframe.customRange.to}`
                    : undefined}
                  className={cn(
                    "rounded-md px-2 py-0.5 text-caption font-medium leading-4 transition-colors",
                    value === "custom"
                      ? "bg-primary/10 text-primary"
                      : "text-muted-foreground hover:bg-accent hover:text-foreground",
                  )}
                >
                  Custom
                </button>
              </PopoverTrigger>
            )}
          </div>
        </div>
      </PopoverAnchor>

      {timeframe && (
        <PopoverContent aria-label="Custom range" className="flex items-end gap-2">
          <label className="flex flex-col gap-1 text-caption font-medium text-muted-foreground">
            From
            <input
              type="date"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
              className="h-7 rounded-md border border-input bg-background px-2 text-xs text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            />
          </label>
          <label className="flex flex-col gap-1 text-caption font-medium text-muted-foreground">
            To
            <input
              type="date"
              value={to}
              onChange={(e) => setTo(e.target.value)}
              className="h-7 rounded-md border border-input bg-background px-2 text-xs text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            />
          </label>
          <Button size="sm" className="h-7" onClick={apply} disabled={!from || !to}>
            Apply
          </Button>
        </PopoverContent>
      )}
    </Popover>
  );
}

/** Tooltip for a button: its long description, plus the dates it covers. */
function rangeTitle(o: TimeframeOption): string {
  return o.from && o.to ? `${o.description} · ${formatDate(o.from)} – ${formatDate(o.to)}` : o.description;
}
