import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { FileSpreadsheet, Plus, RefreshCw, ExternalLink } from "lucide-react";
import { api } from "@/api/client";
import { queries } from "@/api/queries";
import type { OfficeDataset, OfficeSheetExport } from "@/api/types";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import { toast } from "@/components/ui/toast";
import { cn } from "@/lib/utils";
import { invalidate, keys } from "@/api/keys";

interface Props {
  dataset: OfficeDataset;
  /** The table's current filters — sent to the server, which rebuilds the
   *  dataset itself rather than exporting whatever rows happen to be loaded.
   *  Values may be structured (the transaction table's condition list); empty
   *  ones are dropped so they don't widen the stored filter set. */
  filters?: Record<string, unknown>;
  disabled?: boolean;
}

/** Sends a datatable to the household's Office instance as a spreadsheet, and
 *  re-pushes the sheets it made before.
 *
 *  Renders nothing at all when Office isn't configured: this is one household's
 *  side app, so an inert button would be noise on every table for everyone who
 *  doesn't run it. */
export function ExportToOfficeButton({ dataset, filters, disabled }: Props) {
  const queryClient = useQueryClient();
  const { data: config } = useQuery(queries.officeConfiguration());
  const configured = config?.configured ?? false;

  // Only asked for once Office is known to be configured — an unconfigured
  // instance has no sheets to list.
  const { data: sheets } = useQuery({ ...queries.officeSheetExports(dataset), enabled: configured });

  const params = Object.fromEntries(
    Object.entries(filters ?? {}).filter(([, v]) => v !== undefined && v !== null && v !== ""),
  );

  const refreshExports = () => invalidate(queryClient, keys.officeSheetExports);

  const openSheet = (sheet: Pick<OfficeSheetExport, "url">) => {
    if (sheet.url) window.open(sheet.url, "_blank", "noopener");
  };

  // The new sheet opens in its own tab. The tab is opened synchronously on the
  // click and pointed at the sheet once the server answers: a window.open made
  // after an await has lost the click's user activation, and popup blockers
  // (Safari always, Chrome past ~5s) swallow it silently. The mutation's
  // variable is that placeholder tab, carried to the callbacks.
  const create = useMutation<OfficeSheetExport, Error, Window | null>({
    mutationFn: () => api.post<OfficeSheetExport>("/office/sheet_exports", { dataset, ...params }),
    onSuccess: (sheet, tab) => {
      refreshExports();
      if (tab && sheet.url) tab.location.href = sheet.url;
      else tab?.close();
      toast.success(`Created “${sheet.title}” in Office (${sheet.row_count.toLocaleString()} rows)`, {
        action: { label: "Open", onClick: () => openSheet(sheet) },
      });
    },
    onError: (e: Error, tab) => {
      tab?.close();
      toast.error(e.message);
    },
  });

  const startCreate = () => {
    // Not "noopener": that makes window.open return null, and the handle is the
    // whole point. The opener link is cut by hand instead.
    const tab = window.open("", "_blank");
    if (tab) {
      tab.opener = null;
      tab.document.title = "Creating spreadsheet…";
      tab.document.body.textContent = "Creating spreadsheet in Office…";
    }
    create.mutate(tab);
  };

  const refresh = useMutation({
    mutationFn: (sheet: OfficeSheetExport) =>
      api.post<OfficeSheetExport>(`/office/sheet_exports/${sheet.id}/refresh`),
    onSuccess: (sheet) => {
      refreshExports();
      toast.success(`Refreshed “${sheet.title}” (${sheet.row_count.toLocaleString()} rows)`, {
        action: { label: "Open", onClick: () => openSheet(sheet) },
      });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  if (!configured) return null;

  const busy = create.isPending || refresh.isPending;
  const linked = sheets ?? [];

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="icon-sm"
          className="shrink-0 text-muted-foreground hover:text-foreground"
          title="Export to Office"
          aria-label="Export to Office"
          disabled={disabled || busy}
        >
          <FileSpreadsheet size={13} className={cn(busy && "animate-pulse")} />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-64">
        <DropdownMenuItem onSelect={startCreate}>
          <Plus size={14} className="text-muted-foreground" />
          New spreadsheet
        </DropdownMenuItem>

        {linked.length > 0 && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuLabel>Linked sheets</DropdownMenuLabel>
            {linked.map((sheet) => (
              <DropdownMenuItem
                key={sheet.id}
                onSelect={() => refresh.mutate(sheet)}
                title={
                  sheet.last_error
                    ? `Last refresh failed: ${sheet.last_error}`
                    : sheet.last_exported_at
                      ? `Last refreshed ${new Date(sheet.last_exported_at).toLocaleString()}`
                      : undefined
                }
              >
                <RefreshCw size={14} className={cn("text-muted-foreground", sheet.last_error && "text-destructive")} />
                <span className="truncate">{sheet.title}</span>
                {/* Opening is a plain link, not a refresh — stop the row's
                    select handler so the click doesn't also rewrite the sheet. */}
                <button
                  type="button"
                  aria-label={`Open ${sheet.title} in Office`}
                  className="ml-auto shrink-0 text-muted-foreground hover:text-foreground"
                  onClick={(e) => {
                    e.stopPropagation();
                    e.preventDefault();
                    openSheet(sheet);
                  }}
                >
                  <ExternalLink size={13} />
                </button>
              </DropdownMenuItem>
            ))}
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
