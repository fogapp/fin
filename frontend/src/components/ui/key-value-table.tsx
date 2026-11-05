import { cn } from "@/lib/utils";
import { Card, CardContent } from "@/components/ui/card";

export interface KeyValueRow {
  key: string;
  /** Plain-string labels truncate and get a native `title` tooltip automatically. */
  label: React.ReactNode;
  value: React.ReactNode;
  /** Renders a small colored dot before the label (e.g. chart series color). */
  dotColor?: string;
  valueClassName?: string;
}

/**
 * Two-column label/value table for sidebar rails ("Top Categories", "By Account", etc).
 * Owns the truncation contract (`max-w-0 w-full` on the label cell + `truncate` on its
 * content, `whitespace-nowrap` on the value cell) so long labels ellipsize instead of
 * either collapsing to a couple characters or pushing values outside the card.
 */
export function KeyValueTable({ rows, header, mutedLabels = false, className }: {
  rows: KeyValueRow[];
  header?: { label: string; value: string };
  /** Applies text-muted-foreground to the label column. */
  mutedLabels?: boolean;
  className?: string;
}) {
  return (
    <Card className={cn("overflow-hidden", className)}>
      <CardContent className="p-0">
        <table className="w-full text-sm">
          {header && (
            <thead>
              <tr className="border-b text-xs text-muted-foreground">
                <th className="px-4 py-2.5 text-left font-medium">{header.label}</th>
                <th className="px-4 py-2.5 text-right font-medium">{header.value}</th>
              </tr>
            </thead>
          )}
          <tbody className="divide-y">
            {rows.map((row) => (
              <tr key={row.key}>
                <td
                  className={cn("max-w-0 w-full px-4 py-2.5", mutedLabels && "text-muted-foreground")}
                  title={typeof row.label === "string" ? row.label : undefined}
                >
                  {row.dotColor ? (
                    <div className="flex min-w-0 items-center gap-2">
                      <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: row.dotColor }} />
                      <span className="truncate">{row.label}</span>
                    </div>
                  ) : typeof row.label === "string" ? (
                    <span className="block truncate">{row.label}</span>
                  ) : (
                    row.label
                  )}
                </td>
                <td className={cn("px-4 py-2.5 text-right tabular-nums whitespace-nowrap", row.valueClassName)}>
                  {row.value}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  );
}
