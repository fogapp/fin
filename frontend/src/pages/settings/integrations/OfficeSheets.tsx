import { useQuery } from "@tanstack/react-query";
import { ExternalLink } from "lucide-react";
import { queries } from "@/api/queries";
import { formatDate } from "@/lib/utils";

/** Office-only section: the spreadsheets Fin keeps in the instance, so the
 *  settings pane answers "what has it made, and is it still refreshing?"
 *  without opening Office. */
export function OfficeSheets() {
  const { data: sheets } = useQuery(queries.officeSheetExports());

  return (
    <div className="px-8 py-5 border-b">
      <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
        Linked spreadsheets
      </p>
      {!sheets || sheets.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          None yet. The export button on the transactions, holdings and portfolio tables makes one.
        </p>
      ) : (
        <ul className="space-y-2">
          {sheets.map((sheet) => (
            <li key={sheet.id} className="flex items-baseline justify-between gap-3 text-sm">
              <div className="min-w-0">
                <p className="truncate font-medium">{sheet.title}</p>
                <p className="text-xs text-muted-foreground">
                  {sheet.dataset_label} · {sheet.row_count.toLocaleString()} rows
                  {sheet.last_exported_at && <> · refreshed {formatDate(sheet.last_exported_at)}</>}
                </p>
                {sheet.last_error && (
                  <p className="text-xs text-destructive">Last refresh failed: {sheet.last_error}</p>
                )}
              </div>
              {sheet.url && (
                <a
                  href={sheet.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="shrink-0 text-muted-foreground hover:text-foreground"
                  aria-label={`Open ${sheet.title} in Office`}
                >
                  <ExternalLink size={13} />
                </a>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
