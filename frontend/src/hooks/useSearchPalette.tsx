import { createContext, useContext } from "react";

export interface SearchPaletteContextValue {
  openSearch: () => void;
}

export const SearchPaletteContext = createContext<SearchPaletteContextValue | null>(null);

/** Lets any page open the sitewide CommandPalette, e.g. from the header's search icon. */
export function useSearchPalette(): SearchPaletteContextValue {
  const ctx = useContext(SearchPaletteContext);
  if (!ctx) throw new Error("useSearchPalette must be used inside <AppShell>");
  return ctx;
}
