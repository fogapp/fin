/** System widgets: data health (open issues). */
import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { formatDate } from "@/lib/utils";
import { WidgetCard, WidgetError, WidgetShell, WidgetSkeleton } from "../shell";

export function DataHealthWidget() {
  const { data, isLoading, isError, refetch } = useQuery(queries.issues());

  if (isLoading) return <WidgetSkeleton className="h-16" />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Data Health" to="/activity">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const issues = (Array.isArray(data) ? data : []).filter((i) => !i.dismissed_at);
  if (issues.length === 0) {
    // "All clear" is the good news this widget exists to deliver — always show it.
    return shell(
      <WidgetCard className="flex items-center gap-2 space-y-0">
        <span className="h-2 w-2 rounded-full bg-positive" aria-hidden />
        <span className="text-sm text-muted-foreground">No open issues</span>
      </WidgetCard>,
    );
  }

  const errors = issues.filter((i) => i.severity === "error").length;
  const warnings = issues.filter((i) => i.severity === "warning").length;
  const top = issues.slice(0, 2);

  return shell(
    <WidgetCard>
      <div className="flex items-center gap-2 text-sm">
        <span className={`h-2 w-2 rounded-full ${errors > 0 ? "bg-negative" : "bg-warning"}`} aria-hidden />
        <span className="font-medium">{issues.length} open {issues.length === 1 ? "issue" : "issues"}</span>
        <span className="text-xs text-muted-foreground">
          {errors > 0 && `${errors} error${errors === 1 ? "" : "s"}`}
          {errors > 0 && warnings > 0 && " · "}
          {warnings > 0 && `${warnings} warning${warnings === 1 ? "" : "s"}`}
        </span>
      </div>
      {top.map((i) => (
        <div key={i.id} className="text-xs text-muted-foreground">
          <span className="text-foreground">{i.title}</span> · {formatDate(i.created_at.slice(0, 10))}
        </div>
      ))}
    </WidgetCard>,
  );
}
