import type { ComponentType, ReactNode } from "react";
import type { QueryKey, UseQueryOptions } from "@tanstack/react-query";
import { keys } from "@/api/keys";
import { queries } from "@/api/queries";
import { RentcastUsage } from "./RentcastUsage";
import { OfficeSheets } from "./OfficeSheets";

/** The slice of a provider's configuration payload the shared form/detail rely on. */
export interface ApiKeyProviderConfig {
  api_key_set: boolean;
  configured: boolean;
  /** Set by providers whose credentials may also come from the environment. */
  source?: "configuration" | "environment" | null;
  /** Current value of the descriptor's `textField`, echoed back after a save. */
  base_url?: string | null;
}

export type ApiKeyProviderId = "cmc" | "alpha_vantage" | "tiingo" | "rentcast" | "office";

/**
 * Everything that differs between the simple API-key providers (a handful of
 * strings and endpoints) lives here, so the form, detail pane, and settings
 * list can share one implementation. Providers with OAuth, webhooks, or sync
 * UI (Plaid, Coinbase, Alchemy) keep their own bespoke components.
 */
export interface ApiKeyProviderDescriptor {
  id: ApiKeyProviderId;
  name: string;
  /** REST base, e.g. "/tiingo/configuration" — PATCH, DELETE, and /test hang off it. */
  configPath: string;
  /** Rails strong-params wrapper key for PATCH bodies. */
  paramKey: string;
  /** Query caches to refresh after a save or removal. */
  invalidateKeys: QueryKey[];
  query: () => UseQueryOptions<ApiKeyProviderConfig>;
  inputId: string;
  keyPlaceholder: string;
  listBlurb: ReactNode;
  addTitle: string;
  addSubtitle: string;
  configTitle: string;
  configSubtitle: string;
  detailBlurb: ReactNode;
  /** Overrides the default "Test connection" button label. */
  testLabel?: string;
  /** Caveat shown under the action buttons. */
  testNote?: string;
  /** Set when the test endpoint consumes quota, so the counter is pulled back in. */
  testRefetchesConfig?: boolean;
  /** Present only for providers whose connection can be removed from the UI. */
  remove?: { confirmTitle: string; confirmDescription: string };
  /** Extra text field rendered above the key input (Office's instance URL).
   *  Required fields block the save until they have a value or the config
   *  already carries one. */
  textField?: {
    id: string;
    label: string;
    paramKey: string;
    placeholder: string;
    help?: string;
    required?: boolean;
    /** Current value, for the "leave blank to keep" placeholder. */
    current?: (config: ApiKeyProviderConfig | undefined) => string | null | undefined;
  };
  /** Label for the key input when "API Key" isn't what the provider calls it. */
  keyLabel?: string;
  /** Extra numeric field rendered below the key input (RentCast's monthly limit). */
  numberField?: {
    id: string;
    label: string;
    paramKey: string;
    min: number;
    placeholder: (config: ApiKeyProviderConfig | undefined) => string;
    help: string;
  };
  /** Provider-specific section rendered between the detail header and actions. */
  DetailExtra?: ComponentType;
}

/** Each provider's query carries its own key and payload type; the shared
 *  form and detail pane only read the common ApiKeyProviderConfig slice. */
function providerQuery<T extends ApiKeyProviderConfig, K extends QueryKey>(
  options: UseQueryOptions<T, Error, T, K>,
): UseQueryOptions<ApiKeyProviderConfig> {
  return options as unknown as UseQueryOptions<ApiKeyProviderConfig>;
}

export const API_KEY_PROVIDERS: ApiKeyProviderDescriptor[] = [
  {
    id: "cmc",
    name: "CoinMarketCap",
    configPath: "/coin_market_cap/configuration",
    paramKey: "coin_market_cap_configuration",
    invalidateKeys: [keys.coinMarketCapConfiguration],
    query: () => providerQuery(queries.coinMarketCapConfiguration()),
    inputId: "cmc-api-key",
    keyPlaceholder: "Enter your CoinMarketCap API key",
    listBlurb: "Crypto price data",
    addTitle: "Connect CoinMarketCap",
    addSubtitle: "Enter your CoinMarketCap API key to enable crypto price lookups and USD balance calculations.",
    configTitle: "CoinMarketCap credentials",
    configSubtitle: "API key for crypto price data",
    detailBlurb: "Fetches live crypto prices to calculate USD balances for non-USD accounts.",
  },
  {
    id: "alpha_vantage",
    name: "Alpha Vantage",
    configPath: "/alpha_vantage/configuration",
    paramKey: "alpha_vantage_configuration",
    invalidateKeys: [keys.alphaVantageConfiguration],
    query: () => providerQuery(queries.alphaVantageConfiguration()),
    inputId: "av-api-key",
    keyPlaceholder: "Enter your Alpha Vantage API key",
    listBlurb: <>Equity prices, fundamentals &amp; news</>,
    addTitle: "Connect Alpha Vantage",
    addSubtitle: "Enter your Alpha Vantage API key to sync equity & fund prices, company fundamentals, ticker search, and market news.",
    configTitle: "Alpha Vantage credentials",
    configSubtitle: "API key for equity market data",
    detailBlurb: <>Daily equity &amp; fund prices, company fundamentals, ticker search, and market news for the Market page.</>,
  },
  {
    id: "tiingo",
    name: "Tiingo",
    configPath: "/tiingo/configuration",
    paramKey: "tiingo_configuration",
    invalidateKeys: [keys.tiingoConfiguration],
    query: () => providerQuery(queries.tiingoConfiguration()),
    inputId: "tiingo-api-key",
    keyPlaceholder: "Enter your Tiingo API key",
    listBlurb: <>Equity &amp; crypto candles, price cross-checks</>,
    addTitle: "Connect Tiingo",
    addSubtitle: "Enter your Tiingo API key to sync adjusted equity, fund & crypto candles and cross-check prices against other providers.",
    configTitle: "Tiingo credentials",
    configSubtitle: "API key for market data candles",
    detailBlurb: (
      <>
        Preferred source for daily equity, fund &amp; crypto candles; also cross-checks prices against
        Alpha Vantage and CoinGecko to catch bad data.
      </>
    ),
    remove: {
      confirmTitle: "Remove Tiingo?",
      confirmDescription:
        "The API key is deleted and price syncing falls back to Alpha Vantage and CoinGecko. Existing candles are kept.",
    },
  },
  {
    id: "rentcast",
    name: "RentCast",
    configPath: "/rentcast/configuration",
    paramKey: "rentcast_configuration",
    invalidateKeys: [keys.rentcastConfiguration, keys.realEstateProperties],
    query: () => providerQuery(queries.rentcastConfiguration()),
    inputId: "rentcast-api-key",
    keyPlaceholder: "Enter your RentCast API key",
    listBlurb: "Real estate property values",
    addTitle: "Connect RentCast",
    addSubtitle: "Enter your RentCast API key to value real estate properties automatically and seed their history from public records.",
    configTitle: "RentCast credentials",
    configSubtitle: "API key for property value estimates",
    detailBlurb: (
      <>
        Values every real estate property weekly, and seeds each one&rsquo;s history from county tax
        assessments and recorded sales.
      </>
    ),
    testLabel: "Test connection (uses 1 request)",
    testNote: "RentCast has no free credential-check endpoint, so testing spends one of the monthly requests.",
    testRefetchesConfig: true,
    remove: {
      confirmTitle: "Remove RentCast?",
      confirmDescription:
        "The API key is deleted and properties stop being valued automatically. Every property and its recorded value history is kept, and you can keep entering values by hand.",
    },
    numberField: {
      id: "rentcast-limit",
      label: "Monthly request limit",
      paramKey: "monthly_request_limit",
      min: 1,
      placeholder: (config) => String((config as { quota?: { limit: number } } | undefined)?.quota?.limit ?? 50),
      help:
        "The allowance your RentCast plan includes — 50 a month on the free tier. The weekly " +
        "sync budgets against this, so raise it if you upgrade.",
    },
    DetailExtra: RentcastUsage,
  },
  {
    id: "office",
    name: "Office",
    configPath: "/office/configuration",
    paramKey: "office_configuration",
    invalidateKeys: [keys.officeConfiguration, keys.officeSheetExports],
    query: () => providerQuery(queries.officeConfiguration()),
    inputId: "office-api-token",
    keyLabel: "API token",
    keyPlaceholder: "office_…",
    listBlurb: "Spreadsheets from your tables",
    addTitle: "Connect Office",
    addSubtitle:
      "Point Fin at your Office instance and give it an API token minted there (Settings → API tokens). Fin then builds spreadsheets from your tables.",
    configTitle: "Office connection",
    configSubtitle: "Instance URL and API token",
    detailBlurb: (
      <>
        Sends transactions, holdings and the portfolio to Office as spreadsheets, from the export
        button on each table — and refreshes the sheets it already made, in place.
      </>
    ),
    testNote:
      "Every spreadsheet is owned by whoever minted the token, and is private in Office unless you share it there.",
    textField: {
      id: "office-base-url",
      label: "Office URL",
      paramKey: "base_url",
      placeholder: "https://office.example",
      help: "Where the instance is reachable from Fin — the same address you open in a browser.",
      required: true,
      current: (config) => config?.base_url,
    },
    remove: {
      confirmTitle: "Remove Office?",
      confirmDescription:
        "The URL and token are deleted and the export button disappears from every table. Spreadsheets already in Office are left exactly as they are, but Fin forgets which ones it made, so they can no longer be refreshed from here.",
    },
    DetailExtra: OfficeSheets,
  },
];

export function apiKeyProvider(id: ApiKeyProviderId): ApiKeyProviderDescriptor {
  // The table is a static constant, so a missing id is a programming error.
  return API_KEY_PROVIDERS.find((p) => p.id === id)!;
}
