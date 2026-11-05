import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { PageHeader } from "@/components/layout/PageHeader";
import { SectionRailNav } from "@/components/layout/SectionRailNav";
import { useHashParam } from "@/hooks/useHashParam";
import { queries } from "@/api/queries";
import { HouseholdSection } from "@/pages/settings/HouseholdSection";
import { BrokersSection } from "@/pages/settings/BrokersSection";
import { DevicesSection } from "@/pages/settings/DevicesSection";
import { IssuesSection } from "@/pages/settings/IssuesSection";
import { Integrations } from "@/pages/settings/IntegrationsSection";
import { ApiTokens } from "@/pages/settings/ApiTokensSection";
import { BackupSection } from "@/pages/settings/BackupSection";
import { TransactionDefaults } from "@/pages/settings/TransactionDefaultsSection";
import { TransactionSearch } from "@/pages/settings/TransactionSearchSection";
import { TimeframeSettings } from "@/pages/settings/TimeframeSettingsSection";
import { Appearance } from "@/pages/settings/AppearanceSection";
import { MerchantsSettings } from "@/pages/settings/MerchantsSettingsSection";
import { MarketSettings } from "@/pages/settings/MarketSettingsSection";
import { WorkflowSettings } from "@/pages/settings/WorkflowSettingsSection";
import { About } from "@/pages/settings/AboutSection";

const TOPICS: { id: string; label: string; href?: string }[] = [
  { id: "appearance",     label: "Appearance" },
  { id: "transactions",   label: "Transactions" },
  { id: "timeframes",     label: "Timeframes" },
  { id: "household",      label: "Household" },
  { id: "devices",        label: "Devices" },
  { id: "brokers",        label: "Brokers" },
  { id: "merchants",      label: "Merchants" },
  { id: "market",         label: "Market" },
  { id: "workflows",      label: "Workflows" },
  { id: "integrations",   label: "Integrations" },
  { id: "tokens",         label: "API Tokens" },
  { id: "backup",         label: "Backup" },
  { id: "issues",         label: "Issues" },
  // Full pages rather than inline sections — these rows link out.
  { id: "stats",          label: "Stats", href: "/stats" },
  { id: "activity",       label: "Activity", href: "/activity" },
  { id: "about",          label: "About" },
];

export function Settings() {
  const navigate = useNavigate();
  const [rawTopic, setTopic] = useHashParam("topic");
  const activeTopic = rawTopic ?? TOPICS[0].id;
  const { data: issues = [] } = useQuery(queries.issues());
  const issueCount = issues.length;

  const sections = TOPICS.map((t) => ({
    id: t.id,
    label: t.label,
    count: t.id === "issues" ? issueCount : undefined,
    external: Boolean(t.href),
  }));

  return (
    <div className="flex h-full flex-col md:flex-row">
      <SectionRailNav
        title="Settings"
        sections={sections}
        active={activeTopic}
        onSelect={(id) => {
          const topic = TOPICS.find((t) => t.id === id);
          if (topic?.href) navigate(topic.href);
          else setTopic(id);
        }}
      />

      {/* Content */}
      {activeTopic === "integrations" ? (
        <Integrations />
      ) : (
        <div className="flex-1 overflow-y-auto">
          <div className="hidden md:block">
            <PageHeader
              level={1}
              title={TOPICS.find((t) => t.id === activeTopic)?.label ?? "Settings"}
            />
          </div>
          <div className="space-y-6 p-6 max-w-3xl">
            {activeTopic === "appearance"     && <Appearance />}
            {activeTopic === "transactions"   && <><TransactionDefaults /><TransactionSearch /></>}
            {activeTopic === "timeframes"     && <TimeframeSettings />}
            {activeTopic === "household"      && <HouseholdSection />}
            {activeTopic === "devices"        && <DevicesSection />}
            {activeTopic === "brokers"        && <BrokersSection />}
            {activeTopic === "merchants"      && <MerchantsSettings />}
            {activeTopic === "market"         && <MarketSettings />}
            {activeTopic === "workflows"      && <WorkflowSettings />}
            {activeTopic === "tokens"         && <ApiTokens />}
            {activeTopic === "backup"         && <BackupSection />}
            {activeTopic === "issues"         && <IssuesSection />}
            {activeTopic === "about"          && <About />}
          </div>
        </div>
      )}
    </div>
  );
}
