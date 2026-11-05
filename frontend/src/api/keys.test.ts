import { describe, it, expect } from "vitest";
import { keys } from "./keys";

// Source of every non-test module, so the checks below cover the whole app.
const sources = Object.entries(
  import.meta.glob<string>(["/src/**/*.{ts,tsx}", "!/src/**/*.test.{ts,tsx}", "!/src/test/**"], {
    query: "?raw",
    import: "default",
    eager: true,
  }),
);

const keyRef = /keys\.(\w+)/g;

/** Roots that some query is actually stored under (`queryKey: keys.x` or `[...keys.x, …]`). */
function queriedRoots(): Set<string> {
  const roots = new Set<string>();
  for (const [, src] of sources) {
    for (const m of src.matchAll(/queryKey: (?:\[\.\.\.)?keys\.(\w+)/g)) roots.add(m[1]);
  }
  return roots;
}

describe("query keys", () => {
  it("scans the app's modules", () => {
    expect(sources.length).toBeGreaterThan(100);
  });

  it("every key root names at least one query", () => {
    const queried = queriedRoots();
    const unused = Object.keys(keys).filter((k) => !queried.has(k));
    expect(unused).toEqual([]);
  });

  it("every invalidated root names a query that exists", () => {
    const queried = queriedRoots();
    const orphans: string[] = [];
    for (const [file, src] of sources) {
      for (const call of src.matchAll(/invalidate\(\w+,([^;]*?)\)(?:;|,|\n)/g)) {
        for (const ref of call[1].matchAll(keyRef)) {
          if (!queried.has(ref[1])) orphans.push(`${file}: keys.${ref[1]}`);
        }
      }
    }
    expect(orphans).toEqual([]);
  });

  it("no module spells a query key as a string literal", () => {
    const literal = /(queryKey: |setQueryData(?:<[^(]*>)?\(|invalidateKey: )\[\s*"/;
    const offenders = sources
      .filter(([file]) => !file.endsWith("/api/keys.ts"))
      .filter(([, src]) => literal.test(src))
      .map(([file]) => file);
    expect(offenders).toEqual([]);
  });
});
