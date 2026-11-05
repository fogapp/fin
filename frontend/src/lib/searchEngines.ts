// Web search engines offered for looking up a transaction description — the
// detail pane links the description out to the one picked in
// Settings → Transactions.

export interface SearchEngine {
  id: string;
  label: string;
  /** Query string prefix; the encoded search terms are appended to it. */
  queryUrl: string;
}

export const SEARCH_ENGINES: SearchEngine[] = [
  { id: "google",     label: "Google",     queryUrl: "https://www.google.com/search?q=" },
  { id: "duckduckgo", label: "DuckDuckGo", queryUrl: "https://duckduckgo.com/?q=" },
  { id: "kagi",       label: "Kagi",       queryUrl: "https://kagi.com/search?q=" },
  { id: "brave",      label: "Brave",      queryUrl: "https://search.brave.com/search?q=" },
];

export const DEFAULT_SEARCH_ENGINE = SEARCH_ENGINES[0].id;

/** Falls back to the default for an unknown id (a preference written by an
 *  older build, or one whose engine has since been dropped). */
export function searchEngineById(id: string | undefined): SearchEngine {
  return SEARCH_ENGINES.find((e) => e.id === id) ?? SEARCH_ENGINES[0];
}

export function searchUrl(engineId: string | undefined, query: string): string {
  return searchEngineById(engineId).queryUrl + encodeURIComponent(query);
}
