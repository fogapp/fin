/**
 * One cohesive chart widget: a card with a header row (title left, compact
 * control — usually the TimeframeSelector — right), a hairline separator, and
 * the chart body. Timeframe STATE stays page-scoped (one useTimeframe per
 * page); this only gives the control a home inside the chart's own chrome.
 *
 * Every card also gets a PNG export menu (plain and amounts-hidden variants)
 * — it rasterizes whatever SVG the body currently shows, so it works for any
 * chart type without per-page wiring. Cards with no SVG toast instead.
 */
import { useRef } from "react";
import { Download } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { toast } from "@/components/ui/toast";
import { downloadChartPng } from "@/lib/chartExport";

interface ChartCardProps {
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  /** Compact chrome rendered on the right of the header (e.g. TimeframeSelector). */
  control?: React.ReactNode;
  /** Optional stat-tile row rendered between the header and the chart body. */
  stats?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  /** Override the chart body padding (default `p-3 pt-4`). */
  bodyClassName?: string;
}

export function ChartCard({ title, subtitle, control, stats, children, className, bodyClassName }: ChartCardProps) {
  const bodyRef = useRef<HTMLDivElement>(null);

  async function exportPng(hideAmounts: boolean) {
    if (!bodyRef.current) return;
    const name = typeof title === "string" ? title : "chart";
    const ok = await downloadChartPng(bodyRef.current, name, { hideAmounts }).catch(() => false);
    if (!ok) toast.error("No chart to export");
  }

  return (
    <section className={cn("rounded-xl border bg-card text-card-foreground shadow-sm", className)}>
      <header className="flex min-h-10 items-center justify-between gap-3 px-4 py-2">
        <div className="min-w-0">
          <h3 className="truncate text-xs font-medium text-muted-foreground">{title}</h3>
          {subtitle != null && subtitle !== "" && (
            <p className="truncate text-caption text-muted-foreground/70">{subtitle}</p>
          )}
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {control != null && <div className="flex items-center">{control}</div>}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                size="icon-sm"
                className="text-muted-foreground hover:text-foreground"
                title="Download chart"
                aria-label="Download chart"
              >
                <Download size={13} />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-52">
              <DropdownMenuItem onSelect={() => exportPng(false)}>Download PNG</DropdownMenuItem>
              <DropdownMenuItem onSelect={() => exportPng(true)}>Download PNG · amounts hidden</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </header>
      <div className="border-t" aria-hidden />
      {stats != null && (
        <div className="border-b px-4 py-2">
          {stats}
        </div>
      )}
      <div ref={bodyRef} className={cn("p-3 pt-4", bodyClassName)}>{children}</div>
    </section>
  );
}
