import { Suspense, useEffect, useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Sidebar } from "./Sidebar";
import { MobileNav } from "./MobileNav";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { Skeleton } from "@/components/ui/skeleton";
import { CommandPalette } from "@/components/CommandPalette";
import { useTheme } from "@/hooks/useTheme";
import { useFont } from "@/hooks/useFont";
import { useFontSize } from "@/hooks/useFontSize";
import { SearchPaletteContext } from "@/hooks/useSearchPalette";

export function AppShell() {
  // Fetch preferences and apply DOM effects (theme, font, size) immediately
  // on shell mount so every page sees the correct values from the first render.
  useTheme();
  useFont();
  useFontSize();
  const location = useLocation();

  // Cmd+K / Ctrl+K opens sitewide search from anywhere, even while focus is
  // inside an unrelated input — capture phase so it wins ahead of any local
  // keydown handler, matching the app's existing capture-phase-wins
  // convention (comboboxes' Escape handling).
  const [searchOpen, setSearchOpen] = useState(false);
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setSearchOpen((open) => !open);
      }
    }
    window.addEventListener("keydown", onKeyDown, { capture: true });
    return () => window.removeEventListener("keydown", onKeyDown, { capture: true });
  }, []);

  // Warm the charts chunk (recharts, ~123 kB gz) during idle time so the
  // first chart-bearing page doesn't pay a serial route-chunk → charts-chunk
  // waterfall. Dynamic import keeps it out of the main bundle.
  useEffect(() => {
    const prefetch = () => { void import("@/components/charts"); };
    if (typeof window.requestIdleCallback === "function") {
      const id = window.requestIdleCallback(prefetch, { timeout: 3000 });
      return () => window.cancelIdleCallback(id);
    }
    const id = window.setTimeout(prefetch, 1500);
    return () => window.clearTimeout(id);
  }, []);

  // The household switcher + notification bell + search icon live inside
  // each page's own header bar (HeaderActions) rather than a dedicated
  // shell strip; they reach this state via SearchPaletteContext.
  return (
    <SearchPaletteContext.Provider value={{ openSearch: () => setSearchOpen(true) }}>
      <div className="flex h-screen overflow-hidden bg-background">
        <Sidebar />
        <main className="flex flex-1 flex-col overflow-x-hidden pb-16 md:pb-0">
          <div className="min-h-0 flex-1 overflow-y-auto">
            {/* Pages are route-split (React.lazy in App.tsx); the shell stays
                painted while a page chunk loads. Route transitions keep the
                old page visible, so this fallback only shows on first load.
                The route-level boundary keeps the shell alive when a page (or
                its chunk load, post-deploy) throws, and is keyed by pathname
                so navigating away resets it. */}
            <ErrorBoundary key={location.pathname}>
              <Suspense fallback={<PageChunkFallback />}>
                <Outlet />
              </Suspense>
            </ErrorBoundary>
          </div>
        </main>
        <MobileNav />
        <CommandPalette open={searchOpen} onOpenChange={setSearchOpen} />
      </div>
    </SearchPaletteContext.Provider>
  );
}

function PageChunkFallback() {
  return (
    <div className="flex flex-col">
      <div className="h-14 border-b" />
      <div className="space-y-6 p-6">
        <Skeleton className="h-8 w-48 rounded-lg" />
        <Skeleton className="h-48 rounded-xl" />
      </div>
    </div>
  );
}
