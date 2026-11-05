import { useState } from "react";
import { useQueries, useQuery } from "@tanstack/react-query";
import { CheckCircle, Plus, ArrowLeft, Building2, Bitcoin, Link2, Wallet, TrendingUp, CandlestickChart, Home, FileSpreadsheet, type LucideIcon } from "lucide-react";
import { queries } from "@/api/queries";
import { cn } from "@/lib/utils";
import { PlaidDetail } from "@/pages/settings/integrations/PlaidDetail";
import { CoinbaseDetail } from "@/pages/settings/integrations/CoinbaseDetail";
import { AlchemyDetail } from "@/pages/settings/integrations/AlchemyDetail";
import { PlaidCredentialsForm } from "@/pages/settings/integrations/PlaidCredentialsForm";
import { CoinbaseCredentialsForm } from "@/pages/settings/integrations/CoinbaseCredentialsForm";
import { AlchemyCredentialsForm } from "@/pages/settings/integrations/AlchemyCredentialsForm";
import { ApiKeyCredentialsForm } from "@/pages/settings/integrations/ApiKeyCredentialsForm";
import { ApiKeyProviderDetail } from "@/pages/settings/integrations/ApiKeyProviderDetail";
import {
  API_KEY_PROVIDERS,
  apiKeyProvider,
  type ApiKeyProviderDescriptor,
  type ApiKeyProviderId,
} from "@/pages/settings/integrations/apiKeyProviders";

type SelectedView =
  | { kind: "add_connection" }
  | { kind: "add_plaid" }
  | { kind: "add_coinbase" }
  | { kind: "add_alchemy" }
  | { kind: "plaid" }
  | { kind: "plaid_credentials" }
  | { kind: "coinbase" }
  | { kind: "coinbase_config" }
  | { kind: "alchemy" }
  | { kind: "alchemy_config" }
  | { kind: "api_key_add"; provider: ApiKeyProviderDescriptor }
  | { kind: "api_key_detail"; provider: ApiKeyProviderDescriptor }
  | { kind: "api_key_config"; provider: ApiKeyProviderDescriptor };

interface ConnectionEntry {
  key: string;
  name: string;
  blurb: React.ReactNode;
  configured: boolean;
  isSelected: boolean;
  select: () => void;
}

export function Integrations() {
  const [selected, setSelected] = useState<SelectedView | null>(null);

  const { data: plaidConfig } = useQuery(queries.plaidConfiguration());
  const { data: coinbaseConfig } = useQuery(queries.coinbaseConfiguration());
  const { data: alchemyConfig } = useQuery(queries.alchemyConfiguration());
  const apiKeyConfigs = useQueries({ queries: API_KEY_PROVIDERS.map((p) => p.query()) });

  const apiKeyEntry = (id: ApiKeyProviderId): ConnectionEntry => {
    const index = API_KEY_PROVIDERS.findIndex((p) => p.id === id);
    const provider = API_KEY_PROVIDERS[index];
    return {
      key: provider.id,
      name: provider.name,
      blurb: provider.listBlurb,
      configured: apiKeyConfigs[index].data?.configured ?? false,
      isSelected:
        (selected?.kind === "api_key_detail" || selected?.kind === "api_key_config") &&
        selected.provider.id === provider.id,
      select: () => setSelected({ kind: "api_key_detail", provider }),
    };
  };

  const customEntry = (
    key: string,
    name: string,
    blurb: React.ReactNode,
    configured: boolean,
    detailKind: "plaid" | "coinbase" | "alchemy",
    configKind: "plaid_credentials" | "coinbase_config" | "alchemy_config",
  ): ConnectionEntry => ({
    key,
    name,
    blurb,
    configured,
    isSelected: selected?.kind === detailKind || selected?.kind === configKind,
    select: () => setSelected({ kind: detailKind }),
  });

  // Rendered top-to-bottom in this order; blurbs stay beside their provider here
  // rather than in the descriptor table because Plaid/Coinbase/Alchemy have no entry there.
  const entries: ConnectionEntry[] = [
    customEntry("plaid", "Plaid", <>Bank &amp; investment accounts</>, plaidConfig?.configured ?? false, "plaid", "plaid_credentials"),
    customEntry("coinbase", "Coinbase", "Advanced Trade API", coinbaseConfig?.configured ?? false, "coinbase", "coinbase_config"),
    apiKeyEntry("cmc"),
    customEntry("alchemy", "Alchemy", "On-chain wallet balances", alchemyConfig?.configured ?? false, "alchemy", "alchemy_config"),
    apiKeyEntry("alpha_vantage"),
    apiKeyEntry("tiingo"),
    apiKeyEntry("rentcast"),
    apiKeyEntry("office"),
  ];

  return (
    <div className="flex flex-1 overflow-hidden">
      {/* Middle column — connected accounts */}
      <div className="w-60 shrink-0 border-r flex flex-col overflow-hidden">
        <div className="h-14 flex items-center justify-between border-b px-4 shrink-0">
          <p className="text-sm font-medium">Connections</p>
          <button
            onClick={() => setSelected({ kind: "add_connection" })}
            title="Add connection"
            aria-label="Add connection"
            className={cn(
              "rounded-md p-1 text-muted-foreground transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
              selected?.kind === "add_connection" && "bg-primary/8 text-primary"
            )}
          >
            <Plus size={15} />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto p-2 space-y-1">

          {entries.filter((e) => e.configured).map((e) => (
            <button
              key={e.key}
              onClick={e.select}
              className={cn(
                "w-full rounded-lg px-3 py-2.5 text-left transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                e.isSelected ? "bg-primary/8 text-primary" : "text-foreground"
              )}
            >
              <div className="flex items-center gap-2">
                <CheckCircle size={13} className="text-positive shrink-0" />
                <span className="text-sm font-medium">{e.name}</span>
              </div>
              <p className="text-xs text-muted-foreground mt-0.5 ml-[21px]">{e.blurb}</p>
            </button>
          ))}

          {entries.every((e) => !e.configured) && (
            <div className="px-3 py-4 text-center">
              <p className="text-xs text-muted-foreground mb-2">No connections yet</p>
              <button
                onClick={() => setSelected({ kind: "add_connection" })}
                className="rounded text-xs text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                Add your first connection
              </button>
            </div>
          )}

        </div>
      </div>

      {/* Right pane — detail view */}
      <div className="flex-1 overflow-y-auto">
        {selected === null && (
          <div className="flex h-full items-center justify-center">
            <p className="text-sm text-muted-foreground">Select a connection to view details</p>
          </div>
        )}
        {selected?.kind === "add_connection" && (
          <AddConnectionPanel onSelect={setSelected} />
        )}
        {selected?.kind === "add_plaid" && (
          <AddConnectionForm
            title="Connect Plaid"
            subtitle="Enter your Plaid API credentials to start syncing bank and investment accounts."
            onBack={() => setSelected({ kind: "add_connection" })}
          >
            <PlaidCredentialsForm onDone={() => setSelected({ kind: "plaid" })} />
          </AddConnectionForm>
        )}
        {selected?.kind === "add_coinbase" && (
          <AddConnectionForm
            title="Connect Coinbase"
            subtitle="Enter your Coinbase Advanced Trade API credentials to sync crypto transactions."
            onBack={() => setSelected({ kind: "add_connection" })}
          >
            <CoinbaseCredentialsForm onDone={() => setSelected({ kind: "coinbase" })} />
          </AddConnectionForm>
        )}
        {selected?.kind === "plaid" && (
          <PlaidDetail onEditCredentials={() => setSelected({ kind: "plaid_credentials" })} />
        )}
        {selected?.kind === "plaid_credentials" && (
          <IntegrationConfigPane title="Plaid credentials" subtitle="API credentials for bank account connections">
            <PlaidCredentialsForm onDone={() => setSelected({ kind: "plaid" })} />
          </IntegrationConfigPane>
        )}
        {selected?.kind === "coinbase" && (
          <CoinbaseDetail onEditCredentials={() => setSelected({ kind: "coinbase_config" })} />
        )}
        {selected?.kind === "coinbase_config" && (
          <IntegrationConfigPane title="Coinbase credentials" subtitle="Advanced Trade API credentials">
            <CoinbaseCredentialsForm onDone={() => setSelected({ kind: "coinbase" })} />
          </IntegrationConfigPane>
        )}
        {selected?.kind === "add_alchemy" && (
          <AddConnectionForm
            title="Connect Alchemy"
            subtitle="Enter your Alchemy API key to track on-chain wallet balances across Ethereum, Base, and other EVM networks."
            onBack={() => setSelected({ kind: "add_connection" })}
          >
            <AlchemyCredentialsForm onDone={() => setSelected({ kind: "alchemy" })} />
          </AddConnectionForm>
        )}
        {selected?.kind === "alchemy" && (
          <AlchemyDetail onEditCredentials={() => setSelected({ kind: "alchemy_config" })} />
        )}
        {selected?.kind === "alchemy_config" && (
          <IntegrationConfigPane title="Alchemy credentials" subtitle="Portfolio API key for on-chain balances">
            <AlchemyCredentialsForm onDone={() => setSelected({ kind: "alchemy" })} />
          </IntegrationConfigPane>
        )}
        {selected?.kind === "api_key_add" && (
          <AddConnectionForm
            title={selected.provider.addTitle}
            subtitle={selected.provider.addSubtitle}
            onBack={() => setSelected({ kind: "add_connection" })}
          >
            <ApiKeyCredentialsForm
              key={selected.provider.id}
              provider={selected.provider}
              onDone={() => setSelected({ kind: "api_key_detail", provider: selected.provider })}
            />
          </AddConnectionForm>
        )}
        {selected?.kind === "api_key_detail" && (
          <ApiKeyProviderDetail
            key={selected.provider.id}
            provider={selected.provider}
            onEditCredentials={() => setSelected({ kind: "api_key_config", provider: selected.provider })}
            onRemoved={() => setSelected(null)}
          />
        )}
        {selected?.kind === "api_key_config" && (
          <IntegrationConfigPane title={selected.provider.configTitle} subtitle={selected.provider.configSubtitle}>
            <ApiKeyCredentialsForm
              key={selected.provider.id}
              provider={selected.provider}
              onDone={() => setSelected({ kind: "api_key_detail", provider: selected.provider })}
            />
          </IntegrationConfigPane>
        )}
      </div>
    </div>
  );
}

function IntegrationConfigPane({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: React.ReactNode;
}) {
  return (
    <div className="px-8 py-8 max-w-lg">
      <h2 className="text-base font-semibold text-foreground">{title}</h2>
      <p className="mt-1 text-sm text-muted-foreground mb-6">{subtitle}</p>
      {children}
    </div>
  );
}

const PROVIDERS: { name: string; description: string; icon: LucideIcon; view: SelectedView }[] = [
  {
    name: "Plaid",
    description: "Connect banks, credit cards, and investment accounts via the Plaid API.",
    icon: Building2,
    view: { kind: "add_plaid" },
  },
  {
    name: "Coinbase",
    description: "Sync crypto balances and trades from your Coinbase Advanced Trade account.",
    icon: Bitcoin,
    view: { kind: "add_coinbase" },
  },
  {
    name: "CoinMarketCap",
    description: "Fetch live crypto prices to calculate USD values for non-USD account balances.",
    icon: Link2,
    view: { kind: "api_key_add", provider: apiKeyProvider("cmc") },
  },
  {
    name: "Alchemy",
    description: "Track self-custody wallet balances on-chain across Ethereum, Base, and other EVM networks.",
    icon: Wallet,
    view: { kind: "add_alchemy" },
  },
  {
    name: "Alpha Vantage",
    description: "Equity & fund prices, company fundamentals, ticker search, and news for the Market page.",
    icon: TrendingUp,
    view: { kind: "api_key_add", provider: apiKeyProvider("alpha_vantage") },
  },
  {
    name: "Tiingo",
    description: "Adjusted daily candles for equities, funds & crypto — preferred price source, with cross-provider integrity checks.",
    icon: CandlestickChart,
    view: { kind: "api_key_add", provider: apiKeyProvider("tiingo") },
  },
  {
    name: "Office",
    description: "Send transactions, holdings and the portfolio to your Office instance as spreadsheets, and refresh them in place.",
    icon: FileSpreadsheet,
    view: { kind: "api_key_add", provider: apiKeyProvider("office") },
  },
  {
    name: "RentCast",
    description: "Weekly property value estimates for your real estate, seeded with county tax assessments and recorded sales.",
    icon: Home,
    view: { kind: "api_key_add", provider: apiKeyProvider("rentcast") },
  },
];

function AddConnectionForm({
  title,
  subtitle,
  onBack,
  children,
}: {
  title: string;
  subtitle: string;
  onBack: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="px-8 py-8 max-w-lg">
      <button
        onClick={onBack}
        className="mb-6 flex items-center gap-1.5 rounded text-xs text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <ArrowLeft size={13} />
        All providers
      </button>
      <h2 className="text-base font-semibold text-foreground">{title}</h2>
      <p className="mt-1 text-sm text-muted-foreground mb-6">{subtitle}</p>
      {children}
    </div>
  );
}

function AddConnectionPanel({ onSelect }: { onSelect: (view: SelectedView) => void }) {
  return (
    <div className="px-8 py-8 max-w-2xl">
      <h2 className="text-base font-semibold text-foreground">Add connection</h2>
      <p className="mt-1 text-sm text-muted-foreground mb-8">Choose a provider to connect.</p>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {PROVIDERS.map((p) => {
          const Icon = p.icon;
          return (
            <button
              key={p.name}
              onClick={() => onSelect(p.view)}
              className="group flex flex-col gap-4 rounded-xl border bg-card p-6 text-left transition-colors hover:border-primary/40 hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/8 text-primary group-hover:bg-primary/12 transition-colors">
                <Icon size={20} />
              </div>
              <div>
                <p className="text-sm font-semibold text-foreground mb-1">{p.name}</p>
                <p className="text-xs text-muted-foreground leading-relaxed">{p.description}</p>
              </div>
              <p className="text-xs font-medium text-primary mt-auto">Connect →</p>
            </button>
          );
        })}
      </div>
    </div>
  );
}
