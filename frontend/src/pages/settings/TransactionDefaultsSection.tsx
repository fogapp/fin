import { Tabs } from "@/components/ui/tabs";
import { useTransactionDefaults, PAGE_SIZE_OPTIONS } from "@/hooks/useTransactionDefaults";
import { DisplayOptionsPanel } from "@/components/FilterBar";
import { SettingsSection, SettingsSubsection, SettingsResetButton } from "@/pages/settings/SettingsSection";
import { SettingsToggle } from "@/pages/settings/shared";

export function TransactionDefaults() {
  const d = useTransactionDefaults();

  return (
    <SettingsSection
      title="Table Defaults"
      description="Default sort, grouping, and visible columns applied when any transaction table first loads."
    >
      <DisplayOptionsPanel
        columns={d.columns}
        onColumnsChange={d.setColumns}
        groupBy={d.groupBy}
        onGroupByChange={d.setGroupBy}
        primarySort={d.primarySort}
        onPrimarySort={d.setPrimarySort}
        secondarySort={d.secondarySort}
        onSecondarySort={d.setSecondarySort}
        className="w-full space-y-6 p-0"
      />

      <SettingsSubsection label="Rows per page">
        <Tabs
          size="sm"
          value={String(d.pageSize)}
          onChange={(v) => d.setPageSize(Number(v) as typeof PAGE_SIZE_OPTIONS[number])}
          options={PAGE_SIZE_OPTIONS.map((n) => ({ value: String(n), label: String(n) }))}
        />
      </SettingsSubsection>

      <SettingsSubsection className="space-y-3">
        <SettingsToggle
          checked={d.combineMerchantDesc}
          onChange={() => d.setCombineMerchantDesc(!d.combineMerchantDesc)}
          label="Combine merchant & description"
          description="Shows one column using the merchant name, falling back to the transaction description."
        />
        {d.combineMerchantDesc && (
          <SettingsToggle
            checked={d.codeStyleFallback}
            onChange={() => d.setCodeStyleFallback(!d.codeStyleFallback)}
            label="Style description as code"
            description={
              <>
                Renders the fallback description in{" "}
                <code className="rounded bg-muted px-1 py-px font-mono text-xs">monospace</code>{" "}
                when no merchant is set.
              </>
            }
            indent
          />
        )}
      </SettingsSubsection>

      <SettingsResetButton onClick={d.reset} />
    </SettingsSection>
  );
}
