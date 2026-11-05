import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Tabs } from "@/components/ui/tabs";
import { SettingsSection, SettingsSubsection } from "@/pages/settings/SettingsSection";
import type { WorkflowLogLevel } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

const LEVELS: { value: WorkflowLogLevel; label: string; description: string }[] = [
  {
    value: "none",
    label: "None",
    description:
      "Keeps only runs that changed something. Runs whose conditions didn't match — or matched but had nothing to do — are discarded. Failures are always recorded.",
  },
  {
    value: "info",
    label: "Info",
    description:
      "Skips runs whose conditions never matched, so record activity feeds only show workflows that engaged. Activity is logged when a run applies an action or fails.",
  },
  {
    value: "debug",
    label: "Debug",
    description:
      "Keeps every run, including ones that matched nothing, with an activity entry per run. Verbose — useful while building or troubleshooting a workflow.",
  },
];

export function WorkflowSettings() {
  const qc = useQueryClient();
  const { data: me } = useQuery(queries.me());
  const isAdmin = me?.household.role === "admin";
  const level = me?.household.workflow_log_level ?? "info";

  const update = useMutation({
    mutationFn: (workflow_log_level: WorkflowLogLevel) =>
      api.patch(`/households/${me?.household.id}`, { workflow_log_level }),
    onSuccess: () => {
      invalidate(qc, keys.me, keys.households);
    },
  });

  return (
    <SettingsSection
      title="Run logging"
      description="How much workflow run history is kept. Lower levels keep run lists and activity feeds focused on runs that actually did something."
    >
      <SettingsSubsection label="Log level">
        <Tabs
          size="sm"
          value={level}
          onChange={(v) => {
            if (isAdmin && v !== level) update.mutate(v as WorkflowLogLevel);
          }}
          options={LEVELS.map((l) => ({ value: l.value, label: l.label }))}
        />
        <p className="text-sm text-muted-foreground">
          {LEVELS.find((l) => l.value === level)?.description}
        </p>
        {!isAdmin && (
          <p className="text-xs text-muted-foreground">
            Only household admins can change this setting.
          </p>
        )}
      </SettingsSubsection>
    </SettingsSection>
  );
}
