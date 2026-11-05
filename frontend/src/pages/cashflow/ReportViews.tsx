import { useLocation, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { queries } from "@/api/queries";
import { SavedItemsMenu } from "@/components/SavedItemsMenu";
import type { Timeframe } from "@/components/charts";
import type { SavedReport, SavedReportConfig } from "@/api/types";
import type { CashflowScopeState } from "./ScopeFilter";
import { invalidate, keys } from "@/api/keys";

// Saved report views: name the current page state (section + mode toggles via
// the hash, timeframe, account/tag scope) and reopen it in one click. The
// page-level counterpart of the transaction table's saved views.
export function ReportViews({ timeframe, scope, onScopeChange }: {
  timeframe: Timeframe;
  scope: CashflowScopeState;
  onScopeChange: (next: CashflowScopeState) => void;
}) {
  const location = useLocation();
  const navigate = useNavigate();
  const qc = useQueryClient();

  const { data: reports = [] } = useQuery(queries.savedReports());

  const createReport = useMutation({
    mutationFn: (reportName: string) => {
      const config: SavedReportConfig = {
        hash: (window.location.hash || location.hash).replace(/^#/, ""),
        preset: timeframe.preset,
        // The resolved window rides along as a fallback: a user-defined
        // timeframe button may be deleted after the report is saved.
        custom_range: timeframe.preset === "custom"
          ? timeframe.customRange
          : timeframe.from && timeframe.to ? { from: timeframe.from, to: timeframe.to } : null,
        account_id: scope.accountId ?? null,
        tag_id: scope.tagId ?? null,
        exclude_tag_ids: scope.excludeTagIds ?? null,
      };
      return api.post<SavedReport>("/saved_reports", { name: reportName, config });
    },
    onSuccess: () => invalidate(qc, keys.savedReports),
  });

  const deleteReport = useMutation({
    mutationFn: (id: string) => api.delete(`/saved_reports/${id}`),
    onSuccess: () => invalidate(qc, keys.savedReports),
  });

  function apply(report: SavedReport) {
    const config = report.config ?? {};
    if (config.hash != null) navigate({ hash: config.hash });
    if (config.preset && timeframe.options.some((o) => o.key === config.preset)) {
      timeframe.setPreset(config.preset);
    } else if (config.custom_range) {
      timeframe.setCustom(config.custom_range);
    }
    onScopeChange({
      accountId: config.account_id ?? undefined,
      tagId: config.tag_id ?? undefined,
      excludeTagIds: config.exclude_tag_ids ?? undefined,
    });
  }

  return (
    <SavedItemsMenu
      noun="report"
      saveLabel="Save current view as report"
      items={reports}
      saving={createReport.isPending}
      onSave={(name) => createReport.mutateAsync(name)}
      onApply={apply}
      onDelete={(report) => deleteReport.mutate(report.id)}
    />
  );
}
