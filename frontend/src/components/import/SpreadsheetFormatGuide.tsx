import { useQuery } from "@tanstack/react-query";
import { ChevronDown, Download } from "lucide-react";
import { queries } from "@/api/queries";
import type { SpreadsheetFormat } from "@/api/types";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { downloadCsv } from "@/lib/csv";
import { cn } from "@/lib/utils";

/** The spreadsheet layout a backfill needs, as the server checks it — with a
 *  template to start from. Collapsed to one line until asked for, or until a
 *  file fails the check and the person needs it. */
export function SpreadsheetFormatGuide({ open, onToggle }: { open: boolean; onToggle: () => void }) {
  const { data: format, isError } = useQuery({ ...queries.importSpreadsheetFormat(), enabled: open });

  return (
    <div className="rounded-lg border bg-muted/20">
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={open}
        className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-xs text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <span className="flex-1">
          Importing your own spreadsheet? Row 1 needs <strong className="font-medium text-foreground">Date</strong>,{" "}
          <strong className="font-medium text-foreground">Description</strong> and{" "}
          <strong className="font-medium text-foreground">Amount</strong> columns.
        </span>
        <span className="shrink-0 font-medium text-primary">{open ? "Hide format" : "Show format"}</span>
        <ChevronDown size={14} className={cn("shrink-0 transition-transform", open && "rotate-180")} />
      </button>

      {open && (
        <div className="space-y-3 border-t px-3 py-3">
          {format ? <FormatTable format={format} /> : isError ? (
            <p className="text-xs text-destructive">Couldn't load the format description.</p>
          ) : (
            <Skeleton className="h-32 w-full" />
          )}
        </div>
      )}
    </div>
  );
}

function FormatTable({ format }: { format: SpreadsheetFormat }) {
  return (
    <>
      <div className="overflow-x-auto rounded-lg border bg-card">
        <table className="w-full text-xs">
          <thead className="bg-muted/40 text-left text-muted-foreground">
            <tr>
              <th className="px-2 py-1.5 font-medium">Column</th>
              <th className="px-2 py-1.5 font-medium">Example</th>
              <th className="px-2 py-1.5 font-medium">What goes in it</th>
            </tr>
          </thead>
          <tbody>
            {format.columns.map((c) => (
              <tr key={c.name} className="border-t align-top">
                <td className="whitespace-nowrap px-2 py-1.5">
                  <code className="font-semibold text-foreground">{c.name}</code>
                  <div className="text-caption text-muted-foreground">{c.required ? "Required" : "Optional"}</div>
                </td>
                <td className="whitespace-nowrap px-2 py-1.5 tabular-nums text-muted-foreground">{c.example}</td>
                <td className="px-2 py-1.5 text-muted-foreground">{c.description}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <ul className="list-disc space-y-1 pl-4 text-xs text-muted-foreground">
        <li>{format.split_amount}</li>
        {format.notes.map((n) => <li key={n}>{n}</li>)}
        <li>From Excel or Numbers, save as <strong className="font-medium text-foreground">CSV UTF-8</strong> and upload it; an Office spreadsheet can be imported directly.</li>
      </ul>

      <Button type="button" variant="outline" size="sm" onClick={() => downloadCsv("fin-transactions-template.csv", templateCsv(format))}>
        <Download size={13} /> Download template
      </Button>
    </>
  );
}

/** A header row of every column plus the examples as one sample row. */
function templateCsv(format: SpreadsheetFormat): string {
  const quote = (s: string) => `"${s.replaceAll('"', '""')}"`;
  return [
    format.columns.map((c) => quote(c.name)).join(","),
    format.columns.map((c) => quote(c.example)).join(","),
  ].join("\n") + "\n";
}
