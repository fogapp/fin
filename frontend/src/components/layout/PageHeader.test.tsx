import { readFileSync } from "node:fs";
import { globSync } from "node:fs";
import { describe, it, expect } from "vitest";
import { renderWithRouter } from "@/test/queryClient";
import { SearchPaletteContext } from "@/hooks/useSearchPalette";
import { AuthContext } from "@/hooks/useAuth";
import { PageHeader } from "./PageHeader";

function renderHeader(sticky: boolean) {
  const { container } = renderWithRouter(
    <AuthContext.Provider value={{ token: "t", isAuthenticated: true, login: () => {}, logout: () => {} }}>
      <SearchPaletteContext.Provider value={{ openSearch: () => {} }}>
        <PageHeader title="Transactions" level={1} sticky={sticky} />
      </SearchPaletteContext.Provider>
    </AuthContext.Provider>,
  );
  return container.firstElementChild as HTMLElement;
}

// The header is a stacking context when it sticks, so the panels HeaderActions
// opens (notification bell, household switcher) can never rise above it. It has
// to outrank the sticky chrome pages put in their own content — see DESIGN.md §5
// "Layering".
const APP_CHROME_Z = 30;

describe("PageHeader layering", () => {
  it("sticks above the page-content band", () => {
    expect(renderHeader(true).className).toContain(`z-${APP_CHROME_Z}`);
  });

  it("creates no stacking context when it doesn't stick", () => {
    expect(renderHeader(false).className).not.toMatch(/\bz-\d/);
  });

  it("keeps every other sticky element below that band", () => {
    const offenders: string[] = [];

    for (const file of globSync("src/**/*.tsx")) {
      if (file.endsWith("PageHeader.tsx")) continue;

      for (const line of readFileSync(file, "utf8").split("\n")) {
        if (!line.includes("sticky")) continue;
        // `z-20` in a className, or `zIndex: 20` in a style object.
        for (const match of line.matchAll(/\bz-\[?(\d+)\]?\b|zIndex:\s*(\d+)/g)) {
          const z = Number(match[1] ?? match[2]);
          if (z >= APP_CHROME_Z) offenders.push(`${file}: ${line.trim()}`);
        }
      }
    }

    expect(offenders).toEqual([]);
  });
});
