import { AlertCircle, ArrowRight, CheckCircle, Circle, XCircle } from "lucide-react";
import type { ImportPreview } from "@/api/types";
import { cn, formatCurrency, formatDate, moneyColor } from "@/lib/utils";

/** What the server found when it read a file or sheet without importing it:
 *  whether it can go in, which columns are there, what to rename, which rows
 *  won't import, and how the first few will land. Shared by the CSV upload
 *  and the Office sheet import, which check through the same preview. */
export function ImportPreviewPanel({ preview }: { preview: ImportPreview }) {
  const spreadsheetish = preview.format === "spreadsheet" || preview.format === "unknown";
  const fileProblems = preview.problems.filter((p) => p.row == null);
  const rowProblems = preview.problems.filter((p) => p.row != null);
  const unlisted = preview.invalid_row_count - rowProblems.length;

  return (
    <div className="space-y-3 text-sm">
      <Verdict preview={preview} />

      {fileProblems.length > 0 && (
        <ul className="space-y-1">
          {fileProblems.map((p) => (
            <li key={p.message} className="flex gap-2 text-destructive">
              <AlertCircle size={14} className="mt-0.5 shrink-0" />
              <span>{p.message}</span>
            </li>
          ))}
        </ul>
      )}

      {spreadsheetish && <ColumnChecklist preview={preview} />}

      {preview.suggestions.length > 0 && (
        <div className="rounded-lg border border-warning/30 bg-warning/10 p-3">
          <p className="mb-1.5 text-xs font-medium text-foreground">Rename these headers in row 1:</p>
          <ul className="space-y-1">
            {preview.suggestions.map((s) => (
              <li key={s.from} className="flex items-center gap-2 text-xs">
                <code className="rounded bg-muted px-1.5 py-0.5">{s.from}</code>
                <ArrowRight size={12} className="text-muted-foreground" />
                <code className="rounded bg-muted px-1.5 py-0.5 font-semibold">{s.to}</code>
              </li>
            ))}
          </ul>
        </div>
      )}

      {rowProblems.length > 0 && (
        <div>
          <p className="mb-1 text-xs font-medium text-muted-foreground">
            {preview.invalid_row_count === 1 ? "1 row won't import" : `${preview.invalid_row_count} rows won't import`}
            {preview.ready && " — the rest will. Fix these and import again to bring them in."}
          </p>
          <ul className="max-h-40 space-y-0.5 overflow-y-auto rounded-lg border bg-muted/30 p-2 text-xs">
            {rowProblems.map((p) => (
              <li key={`${p.row}-${p.message}`} className="flex gap-2">
                <span className="w-14 shrink-0 tabular-nums text-muted-foreground">Row {p.row}</span>
                <span className="text-destructive">{p.message}</span>
              </li>
            ))}
            {unlisted > 0 && <li className="text-muted-foreground">…and {unlisted} more</li>}
          </ul>
        </div>
      )}

      {preview.sample.length > 0 && (
        <div>
          <p className="mb-1 text-xs font-medium text-muted-foreground">How the first rows will import</p>
          <div className="overflow-x-auto rounded-lg border">
            <table className="w-full text-xs">
              <thead className="bg-muted/40 text-left text-muted-foreground">
                <tr>
                  <th className="px-2 py-1.5 font-medium">Row</th>
                  <th className="px-2 py-1.5 font-medium">Date</th>
                  <th className="px-2 py-1.5 font-medium">Description</th>
                  <th className="px-2 py-1.5 font-medium">Type</th>
                  <th className="px-2 py-1.5 text-right font-medium">Amount</th>
                </tr>
              </thead>
              <tbody>
                {preview.sample.map((r) => (
                  <tr key={r.row} className="border-t">
                    <td className="px-2 py-1.5 tabular-nums text-muted-foreground">{r.row}</td>
                    <td className="whitespace-nowrap px-2 py-1.5">{formatDate(r.date)}</td>
                    <td className="max-w-48 truncate px-2 py-1.5">{r.description}</td>
                    <td className="px-2 py-1.5 text-muted-foreground">{r.type}</td>
                    <td className={cn("whitespace-nowrap px-2 py-1.5 text-right tabular-nums", moneyColor(r.amount))}>
                      {formatCurrency(r.amount)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-1 text-caption text-muted-foreground">
            Money out should be negative. If the signs look backwards, flip them in the sheet before importing.
          </p>
        </div>
      )}
    </div>
  );
}

function Verdict({ preview }: { preview: ImportPreview }) {
  const rows = preview.row_count - preview.invalid_row_count;
  const as = preview.imports_as === "credit_card" ? " as credit card activity" : preview.imports_as === "bank" ? " as bank activity" : "";

  if (!preview.ready) {
    return (
      <p className="flex items-center gap-2 font-medium text-destructive">
        <XCircle size={15} className="shrink-0" />
        {preview.format === "unknown" ? "Not in a format Fin can import yet" : `${preview.format_label} — nothing to import yet`}
      </p>
    );
  }
  return (
    <p className="flex items-center gap-2 font-medium text-foreground">
      <CheckCircle size={15} className="shrink-0 text-positive" />
      <span>
        {preview.format_label} · {rows.toLocaleString()} {rows === 1 ? "row" : "rows"} ready to import{as}
      </span>
    </p>
  );
}

/** Each spreadsheet column, ticked off when a header supplies it. */
function ColumnChecklist({ preview }: { preview: ImportPreview }) {
  return (
    <ul className="flex flex-wrap gap-1.5" aria-label="Columns">
      {preview.columns.map((c) => {
        const found = c.found != null;
        const missing = c.required && !found;
        // Show the sheet's own header when it differs only in case/spacing or
        // is the Debit/Credit pair standing in for Amount.
        const via = found && c.found!.trim().toLowerCase() !== c.name.toLowerCase() ? c.found : null;
        return (
          <li
            key={c.name}
            className={cn(
              "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs",
              found && "border-positive/30 bg-positive/10 text-foreground",
              missing && "border-destructive/40 bg-destructive/10 text-destructive",
              !found && !missing && "border-border text-muted-foreground",
            )}
          >
            {found ? <CheckCircle size={11} className="text-positive" /> : missing ? <XCircle size={11} /> : <Circle size={11} />}
            {c.name}
            {via && <span className="text-muted-foreground">({via})</span>}
            {!found && <span className="sr-only">{missing ? "missing, required" : "not present, optional"}</span>}
          </li>
        );
      })}
    </ul>
  );
}
