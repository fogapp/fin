import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CheckCircle, ExternalLink, FileSpreadsheet, Loader2, RefreshCw, Search } from "lucide-react";
import { queries } from "@/api/queries";
import { invalidate, keys } from "@/api/keys";
import type { Import, OfficeSpreadsheet } from "@/api/types";
import { ErrorState } from "@/components/PageState";
import { Button } from "@/components/ui/button";
import { DialogFooter } from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { SkeletonList } from "@/components/ui/skeleton";
import { useDebounced } from "@/hooks/useDebounced";
import { formatDateTime } from "@/lib/utils";
import { ImportPreviewPanel } from "./ImportPreviewPanel";
import { postImport } from "./requests";

interface Props {
  accountId: string;
  onClose: () => void;
  /** Opens the format guide — when a sheet fails the check, the fix is there. */
  onNeedsFormat: () => void;
}

/** Backfill an account from a spreadsheet kept in Office: pick the sheet,
 *  see what the import would make of it, fix it in Office and check again
 *  until it's clean, then import. Fin reads the sheet; it never writes. */
export function OfficeSheetImport({ accountId, onClose, onNeedsFormat }: Props) {
  const [picked, setPicked] = useState<OfficeSpreadsheet | null>(null);
  const [sheet, setSheet] = useState<string | null>(null);
  const [result, setResult] = useState<Import | null>(null);

  if (result && picked) {
    return <ImportResult result={result} title={picked.title} onAnother={() => { setResult(null); setPicked(null); setSheet(null); }} onClose={onClose} />;
  }

  if (!picked) {
    return <SpreadsheetPicker onPick={(doc) => { setPicked(doc); setSheet(null); }} onClose={onClose} />;
  }

  return (
    <SheetCheck
      accountId={accountId}
      doc={picked}
      sheet={sheet}
      onSheet={setSheet}
      onBack={() => { setPicked(null); setSheet(null); }}
      onImported={setResult}
      onNeedsFormat={onNeedsFormat}
      onClose={onClose}
    />
  );
}

function SpreadsheetPicker({ onPick, onClose }: { onPick: (doc: OfficeSpreadsheet) => void; onClose: () => void }) {
  const [query, setQuery] = useState("");
  const debounced = useDebounced(query.trim(), 250);
  const { data: docs, isPending, isError, error, refetch } = useQuery(queries.officeSpreadsheets(debounced));

  return (
    <>
      <div className="space-y-3 px-5 pb-4">
        <div className="relative">
          <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <Input
            aria-label="Search Office spreadsheets"
            placeholder="Search spreadsheets in Office"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="pl-8"
            autoFocus
          />
        </div>

        {isPending ? (
          <SkeletonList rows={4} rowClassName="h-11" />
        ) : isError ? (
          <ErrorState title="Couldn't list Office spreadsheets" message={(error as Error).message} onRetry={() => refetch()} />
        ) : docs.length === 0 ? (
          <EmptyState
            icon={FileSpreadsheet}
            title={debounced ? `No spreadsheets match “${debounced}”` : "No spreadsheets in Office yet"}
            description="Create or upload the sheet in Office first, then find it here."
          />
        ) : (
          <ul className="max-h-72 space-y-1 overflow-y-auto" aria-label="Office spreadsheets">
            {docs.map((doc) => (
              <li key={doc.id}>
                <button
                  type="button"
                  onClick={() => onPick(doc)}
                  className="flex w-full items-center gap-3 rounded-lg border bg-card px-3 py-2 text-left hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  <FileSpreadsheet size={16} className="shrink-0 text-primary" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium">{doc.title}</span>
                    <span className="block truncate text-xs text-muted-foreground">
                      {[doc.folder, doc.updated_at && `Edited ${formatDateTime(doc.updated_at)}`].filter(Boolean).join(" · ")}
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      <DialogFooter>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
      </DialogFooter>
    </>
  );
}

function SheetCheck({ accountId, doc, sheet, onSheet, onBack, onImported, onNeedsFormat, onClose }: {
  accountId: string;
  doc: OfficeSpreadsheet;
  sheet: string | null;
  onSheet: (name: string) => void;
  onBack: () => void;
  onImported: (result: Import) => void;
  onNeedsFormat: () => void;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const { data, isPending, isFetching, isError, error, refetch } = useQuery(
    queries.officeSpreadsheetPreview(doc.id, accountId, sheet),
  );
  const preview = data?.preview;
  const activeSheet = sheet ?? data?.sheet ?? null;

  const importSheet = useMutation<Import, Error>({
    mutationFn: () => postImport(`/office/spreadsheets/${doc.id}/import`, { account_id: accountId, sheet: activeSheet }),
    onSuccess: (result) => {
      if ((result.imported_count ?? 0) > 0) invalidate(qc, keys.cashTransactions, keys.accounts);
      onImported(result);
    },
    // The failure is shown in place, beside the sheet it's about.
    onError: () => {},
  });

  const readyRows = preview ? preview.row_count - preview.invalid_row_count : 0;

  return (
    <>
      <div className="space-y-3 px-5 pb-4">
        <div className="flex items-center gap-2 rounded-lg border bg-muted/30 px-3 py-2">
          <FileSpreadsheet size={16} className="shrink-0 text-primary" />
          <span className="min-w-0 flex-1 truncate text-sm font-medium">{doc.title}</span>
          {doc.url && (
            <a
              href={doc.url}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 rounded text-xs text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              Open in Office <ExternalLink size={11} />
            </a>
          )}
          <Button variant="ghost" size="xs" onClick={onBack}>Change</Button>
        </div>

        {data && data.sheets.length > 1 && (
          <div className="flex items-center gap-2">
            <Label htmlFor="office-sheet" className="shrink-0 text-xs">Sheet</Label>
            <Select id="office-sheet" value={activeSheet ?? ""} onChange={(e) => onSheet(e.target.value)} wrapperClassName="flex-1">
              {data.sheets.map((s) => (
                <option key={s.name} value={s.name}>{s.name}{s.used_range ? ` (${s.used_range})` : " (empty)"}</option>
              ))}
            </Select>
          </div>
        )}

        {isPending ? (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 size={14} className="animate-spin" /> Reading the sheet…
          </p>
        ) : isError ? (
          <ErrorState title="Couldn't read the sheet" message={(error as Error).message} onRetry={() => refetch()} />
        ) : preview ? (
          <>
            <ImportPreviewPanel preview={preview} />
            <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
              {!preview.ready && (
                <Button variant="outline" size="xs" onClick={onNeedsFormat}>See the format</Button>
              )}
              <Button variant="outline" size="xs" onClick={() => refetch()} disabled={isFetching}>
                <RefreshCw size={12} className={isFetching ? "animate-spin" : undefined} /> Check again
              </Button>
              <span>Edited the sheet in Office? Check again to re-read it.</span>
            </div>
          </>
        ) : null}

        {importSheet.isError && (
          <p className="text-sm text-destructive">{importSheet.error.message}</p>
        )}
      </div>

      <DialogFooter>
        <Button variant="outline" onClick={onClose} disabled={importSheet.isPending}>Cancel</Button>
        <Button onClick={() => importSheet.mutate()} disabled={!preview?.ready || isFetching || importSheet.isPending}>
          {importSheet.isPending ? "Importing…" : preview?.ready ? `Import ${readyRows.toLocaleString()} ${readyRows === 1 ? "row" : "rows"}` : "Import"}
        </Button>
      </DialogFooter>
    </>
  );
}

function ImportResult({ result, title, onAnother, onClose }: {
  result: Import;
  title: string;
  onAnother: () => void;
  onClose: () => void;
}) {
  const failed = result.status === "failed";
  return (
    <>
      <div className="space-y-3 px-5 pb-4">
        <p className="flex items-center gap-2 text-sm font-medium">
          {failed
            ? <span className="text-destructive">The import of “{title}” failed</span>
            : <><CheckCircle size={15} className="text-positive" /> Imported “{title}”</>}
        </p>
        {!failed && (
          <dl className="grid grid-cols-3 gap-2 rounded-lg border bg-muted/40 p-3 text-sm">
            <Stat label="Imported" value={result.imported_count ?? 0} />
            <Stat label="Already there" value={result.skipped_count ?? 0} />
            <Stat label="Errors" value={result.error_count ?? 0} bad />
          </dl>
        )}
        {result.error_log && (
          <pre className="max-h-40 overflow-auto whitespace-pre-wrap rounded-lg border bg-muted/30 p-2 text-xs text-destructive">{result.error_log}</pre>
        )}
      </div>
      <DialogFooter>
        <Button variant="outline" onClick={onAnother}>Import another sheet</Button>
        <Button onClick={onClose}>Done</Button>
      </DialogFooter>
    </>
  );
}

function Stat({ label, value, bad }: { label: string; value: number; bad?: boolean }) {
  return (
    <div className="text-center">
      <dt className="mb-0.5 text-xs text-muted-foreground">{label}</dt>
      <dd className={bad && value > 0 ? "font-semibold text-destructive" : "font-semibold text-foreground"}>{value}</dd>
    </div>
  );
}
