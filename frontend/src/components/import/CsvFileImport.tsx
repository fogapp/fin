import { useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { AlertCircle, CheckCircle, ChevronDown, FileText, Loader2, Upload, X, XCircle } from "lucide-react";
import { invalidate, keys } from "@/api/keys";
import type { Import, ImportPreview } from "@/api/types";
import { Button } from "@/components/ui/button";
import { DialogFooter } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { ImportPreviewPanel } from "./ImportPreviewPanel";
import { postImport, previewFile } from "./requests";

type Check =
  | { state: "checking" }
  | { state: "checked"; preview: ImportPreview }
  | { state: "failed"; message: string };

type FileStatus =
  | { state: "pending" }
  | { state: "uploading" }
  | { state: "done"; result: Import }
  | { state: "error"; message: string };

interface FileEntry {
  file: File;
  check: Check;
  status: FileStatus;
  expanded: boolean;
}

interface Props {
  accountId: string;
  onClose: () => void;
  /** True while files are uploading, so the dialog can refuse to close. */
  onBusy: (busy: boolean) => void;
  onNeedsFormat: () => void;
}

const isCsv = (f: File) => f.name.toLowerCase().endsWith(".csv") || f.type === "text/csv";
// Workbooks can't be read here, but they're the likeliest wrong file for a
// spreadsheet backfill, so they get an explanation rather than vanishing.
const isWorkbook = (f: File) => /\.(xlsx|xlsm|xls|numbers|ods)$/i.test(f.name);

const WORKBOOK_HELP =
  "This is a workbook, not a CSV. Save it as CSV UTF-8 (Excel: File › Save a Copy; Numbers: File › Export To › CSV) " +
  "and add the .csv — or upload it to Office and import it from the From Office tab.";

const importable = (e: FileEntry) => e.check.state === "checked" && e.check.preview.ready;

/** CSV files — a bank's export, or a spreadsheet saved as CSV. Each file is
 *  checked by the server as it's added, so a file that won't import says why
 *  before anything is uploaded for real. */
export function CsvFileImport({ accountId, onClose, onBusy, onNeedsFormat }: Props) {
  const qc = useQueryClient();
  const inputRef = useRef<HTMLInputElement>(null);
  const [entries, setEntries] = useState<FileEntry[]>([]);
  const [dragging, setDragging] = useState(false);
  const [running, setRunning] = useState(false);
  const [done, setDone] = useState(false);

  const update = (name: string, change: Partial<FileEntry>) =>
    setEntries((prev) => prev.map((e) => (e.file.name === name ? { ...e, ...change } : e)));

  async function check(file: File) {
    try {
      const preview = await previewFile(file, accountId);
      update(file.name, { check: { state: "checked", preview }, expanded: !preview.ready });
      if (preview.format === "unknown") onNeedsFormat();
    } catch (err) {
      update(file.name, { check: { state: "failed", message: (err as Error).message }, expanded: true });
    }
  }

  function addFiles(files: FileList | File[]) {
    const existing = new Set(entries.map((e) => e.file.name));
    const fresh: FileEntry[] = Array.from(files)
      .filter((f) => (isCsv(f) || isWorkbook(f)) && !existing.has(f.name))
      .map((file) => ({
        file,
        check: isCsv(file) ? { state: "checking" } : { state: "failed", message: WORKBOOK_HELP },
        status: { state: "pending" },
        expanded: !isCsv(file),
      }));
    if (fresh.length === 0) return;
    setEntries((prev) => [...prev, ...fresh]);
    fresh.filter((e) => e.check.state === "checking").forEach((e) => void check(e.file));
  }

  function handleDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragging(false);
    addFiles(e.dataTransfer.files);
  }

  async function handleUpload() {
    setRunning(true);
    onBusy(true);
    let anyImported = false;

    for (const entry of entries) {
      if (!importable(entry) || entry.status.state !== "pending") continue;
      update(entry.file.name, { status: { state: "uploading" } });

      const form = new FormData();
      form.append("file", entry.file);
      form.append("account_id", accountId);
      try {
        const result = await postImport("/imports", form);
        if (result.status === "failed") {
          update(entry.file.name, { status: { state: "error", message: result.error_log || "The import failed" } });
        } else {
          if ((result.imported_count ?? 0) > 0) anyImported = true;
          update(entry.file.name, { status: { state: "done", result } });
        }
      } catch (err) {
        update(entry.file.name, { status: { state: "error", message: (err as Error).message } });
      }
    }

    if (anyImported) invalidate(qc, keys.cashTransactions, keys.accounts);
    setRunning(false);
    onBusy(false);
    setDone(true);
  }

  function reset() {
    setEntries([]);
    setDone(false);
  }

  const ready = entries.filter((e) => importable(e) && e.status.state === "pending");
  const checking = entries.some((e) => e.check.state === "checking");
  const anyFailed = entries.some((e) => e.status.state === "error");
  const totals = entries.reduce(
    (acc, e) => {
      if (e.status.state === "done") {
        acc.imported += e.status.result.imported_count ?? 0;
        acc.skipped += e.status.result.skipped_count ?? 0;
        acc.errors += e.status.result.error_count ?? 0;
      }
      return acc;
    },
    { imported: 0, skipped: 0, errors: 0 },
  );

  return (
    <>
      <div className="space-y-4 px-5 pb-4">
        {!running && !done && (
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
            onDragLeave={() => setDragging(false)}
            onDrop={handleDrop}
            className={cn(
              "flex w-full cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed px-6 py-8 text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
              dragging
                ? "border-primary bg-primary/5 text-primary"
                : "border-muted-foreground/25 text-muted-foreground hover:border-primary/50 hover:bg-muted/40",
            )}
          >
            <Upload size={22} className={dragging ? "text-primary" : "text-muted-foreground"} />
            <span>{entries.length === 0 ? "Drop CSV files here, or click to browse" : "Drop more files or click to add"}</span>
            <span className="text-xs">Bank and credit card exports, or your own spreadsheet saved as CSV</span>
          </button>
        )}

        <input
          ref={inputRef}
          type="file"
          accept=".csv,text/csv,.xlsx,.xls,.numbers,.ods"
          multiple
          aria-label="Choose CSV files"
          className="hidden"
          onChange={(e) => { if (e.target.files) { addFiles(e.target.files); e.target.value = ""; } }}
        />

        {entries.length > 0 && (
          <ul className="max-h-96 space-y-1.5 overflow-y-auto">
            {entries.map((entry) => (
              <FileRow
                key={entry.file.name}
                entry={entry}
                locked={running || done}
                onToggle={() => update(entry.file.name, { expanded: !entry.expanded })}
                onRemove={() => setEntries((prev) => prev.filter((e) => e.file.name !== entry.file.name))}
              />
            ))}
          </ul>
        )}

        {done && entries.filter((e) => e.status.state === "done").length > 1 && (
          <div className="rounded-lg border bg-muted/40 p-3">
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Total across {entries.length} files</p>
            <dl className="grid grid-cols-3 gap-2 text-sm">
              <div className="text-center">
                <dt className="mb-0.5 text-xs text-muted-foreground">Imported</dt>
                <dd className="font-semibold text-foreground">{totals.imported}</dd>
              </div>
              <div className="text-center">
                <dt className="mb-0.5 text-xs text-muted-foreground">Skipped</dt>
                <dd className="font-semibold text-foreground">{totals.skipped}</dd>
              </div>
              <div className="text-center">
                <dt className="mb-0.5 text-xs text-muted-foreground">Errors</dt>
                <dd className={cn("font-semibold", totals.errors > 0 ? "text-destructive" : "text-foreground")}>{totals.errors}</dd>
              </div>
            </dl>
          </div>
        )}
      </div>

      <DialogFooter>
        {done ? (
          <>
            {anyFailed && <Button variant="outline" onClick={reset}>Import more</Button>}
            <Button onClick={onClose}>Done</Button>
          </>
        ) : (
          <>
            <Button variant="outline" onClick={onClose} disabled={running}>Cancel</Button>
            <Button onClick={handleUpload} disabled={ready.length === 0 || checking || running}>
              {running
                ? "Importing…"
                : checking
                  ? "Checking…"
                  : `Import${ready.length > 0 ? ` ${ready.length} file${ready.length > 1 ? "s" : ""}` : ""}`}
            </Button>
          </>
        )}
      </DialogFooter>
    </>
  );
}

function FileRow({ entry, locked, onToggle, onRemove }: {
  entry: FileEntry;
  locked: boolean;
  onToggle: () => void;
  onRemove: () => void;
}) {
  const { check, status } = entry;
  const preview = check.state === "checked" ? check.preview : null;
  const result = status.state === "done" ? status.result : null;

  let icon: React.ReactNode;
  let summary: React.ReactNode;
  if (status.state === "uploading") {
    icon = <Loader2 size={14} className="shrink-0 animate-spin text-primary" />;
  } else if (status.state === "done") {
    icon = <CheckCircle size={14} className="shrink-0 text-positive" />;
  } else if (status.state === "error") {
    icon = <AlertCircle size={14} className="shrink-0 text-destructive" />;
  } else if (check.state === "checking") {
    icon = <Loader2 size={14} className="shrink-0 animate-spin text-muted-foreground" />;
    summary = <span className="text-muted-foreground">Checking…</span>;
  } else if (check.state === "failed" || !preview?.ready) {
    icon = <XCircle size={14} className="shrink-0 text-destructive" />;
    summary = <span className="text-destructive">{check.state === "failed" ? "Can't import" : "Needs changes"}</span>;
  } else {
    icon = <FileText size={14} className="shrink-0 text-muted-foreground" />;
    const rows = preview.row_count - preview.invalid_row_count;
    summary = (
      <span className={preview.invalid_row_count > 0 ? "text-warning" : "text-muted-foreground"}>
        {preview.format_label} · {rows} {rows === 1 ? "row" : "rows"}
        {preview.invalid_row_count > 0 && ` · ${preview.invalid_row_count} won't import`}
      </span>
    );
  }

  const expandable = !result && status.state !== "error" && check.state !== "checking";

  return (
    <li className="rounded-lg border bg-muted/30 px-3 py-2">
      <div className="flex items-center gap-2">
        {icon}
        <span className="min-w-0 flex-1 truncate text-sm font-medium">{entry.file.name}</span>
        {summary && <span className="shrink-0 text-xs">{summary}</span>}
        {expandable && (
          <button
            type="button"
            onClick={onToggle}
            aria-expanded={entry.expanded}
            aria-label={`${entry.expanded ? "Hide" : "Show"} details for ${entry.file.name}`}
            className="rounded p-0.5 text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <ChevronDown size={14} className={cn("transition-transform", entry.expanded && "rotate-180")} />
          </button>
        )}
        {status.state === "pending" && !locked && (
          <button
            type="button"
            onClick={onRemove}
            aria-label={`Remove ${entry.file.name}`}
            className="rounded p-0.5 text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <X size={12} />
          </button>
        )}
      </div>

      {expandable && entry.expanded && (
        <div className="mt-2 border-t pt-2">
          {check.state === "failed" ? <p className="text-sm text-destructive">{check.message}</p> : preview && <ImportPreviewPanel preview={preview} />}
        </div>
      )}

      {result && (
        <div className="mt-1.5 flex items-center gap-4 pl-5 text-xs text-muted-foreground">
          <span>{result.imported_count ?? 0} imported</span>
          <span>{result.skipped_count ?? 0} skipped</span>
          {(result.error_count ?? 0) > 0 && <span className="text-destructive">{result.error_count} errors</span>}
          {result.kind && <span className="capitalize">{result.kind.replace(/_/g, " ")}</span>}
        </div>
      )}
      {result?.error_log && (
        <pre className="mt-1 max-h-32 overflow-auto whitespace-pre-wrap pl-5 text-xs text-destructive">{result.error_log}</pre>
      )}
      {status.state === "error" && <p className="mt-1 whitespace-pre-wrap pl-5 text-xs text-destructive">{status.message}</p>}
    </li>
  );
}
