import { Tabs } from "@/components/ui/tabs";
import { useTransactionDefaults } from "@/hooks/useTransactionDefaults";
import { SEARCH_ENGINES, searchEngineById } from "@/lib/searchEngines";
import { SettingsSection, SettingsSubsection } from "@/pages/settings/SettingsSection";

export function TransactionSearch() {
  const { searchEngine, setSearchEngine } = useTransactionDefaults();
  const engine = searchEngineById(searchEngine);

  return (
    <SettingsSection
      title="Description Search"
      description="Clicking a transaction's description in the detail pane opens a web search for it — useful for identifying a raw bank descriptor."
    >
      <SettingsSubsection label="Search engine">
        <Tabs
          size="sm"
          aria-label="Search engine"
          value={engine.id}
          onChange={setSearchEngine}
          options={SEARCH_ENGINES.map((e) => ({ value: e.id, label: e.label }))}
        />
      </SettingsSubsection>
    </SettingsSection>
  );
}
