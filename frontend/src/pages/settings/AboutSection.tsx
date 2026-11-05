import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { Badge } from "@/components/ui/badge";
import { SettingsSection } from "@/pages/settings/SettingsSection";
import { SkeletonList } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";

export function About() {
  const { data, isLoading, isError, refetch } = useQuery(queries.about());

  const rows: { label: string; value: React.ReactNode }[] = data ? [
    { label: "Git SHA",        value: data.git_sha
        ? <span className="font-mono" title={data.git_sha ?? undefined}>{data.git_sha_short ?? data.git_sha}</span>
        : <span className="text-muted-foreground">unavailable</span> },
    { label: "Rails",          value: data.rails_version },
    { label: "Ruby",           value: data.ruby_version },
    { label: "Environment",    value: <Badge variant="outline" className="capitalize">{data.rails_env}</Badge> },
    { label: "Hostname",       value: <span className="font-mono">{data.hostname}</span> },
  ] : [];

  return (
    <SettingsSection title="About" description="Runtime information about this Fin instance.">
      {isLoading ? (
        <SkeletonList rows={5} />
      ) : isError ? (
        <ErrorState title="Failed to load runtime info" onRetry={() => refetch()} />
      ) : (
        <div className="divide-y rounded-lg border">
          {rows.map(({ label, value }) => (
            <div key={label} className="flex items-center justify-between px-4 py-3">
              <span className="text-sm text-muted-foreground">{label}</span>
              <span className="text-sm">{value}</span>
            </div>
          ))}
        </div>
      )}
    </SettingsSection>
  );
}
