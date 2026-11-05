import { describe, expect, it } from "vitest";
import { DEFAULT_WIDGET_IDS, WIDGET_CATEGORIES, WIDGET_MAP, WIDGETS } from "./registry";

describe("dashboard widget registry", () => {
  it("has unique ids", () => {
    const ids = WIDGETS.map((w) => w.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("gives every widget a title, description and known category", () => {
    for (const w of WIDGETS) {
      expect(w.title).toBeTruthy();
      expect(w.description).toBeTruthy();
      expect(WIDGET_CATEGORIES).toContain(w.category);
    }
  });

  it("only lists registered widgets in the defaults", () => {
    for (const id of DEFAULT_WIDGET_IDS) {
      expect(WIDGET_MAP.has(id)).toBe(true);
    }
  });
});
