import { describe, it, expect } from "vitest";
import {
  DEFAULT_TIMEFRAME_SETTINGS, pageDefaultKey, parseTimeframeSettings, resolveButton, rollingRange,
  suggestFixedLabel, suggestRollingLabel, type TimeframeSettings,
} from "./timeframeButtons";

const today = new Date(2026, 8, 21); // 2026-09-21 (local)

describe("rollingRange", () => {
  it("counts back N units from today", () => {
    expect(rollingRange(90, "days", today)).toEqual({ from: "2026-06-23", to: "2026-09-21" });
    expect(rollingRange(2, "weeks", today)).toEqual({ from: "2026-09-07", to: "2026-09-21" });
    expect(rollingRange(18, "months", today)).toEqual({ from: "2025-03-21", to: "2026-09-21" });
    expect(rollingRange(2, "years", today)).toEqual({ from: "2024-09-21", to: "2026-09-21" });
  });
});

describe("suggested labels", () => {
  it("abbreviates rolling windows", () => {
    expect(suggestRollingLabel(2, "years")).toBe("2Y");
    expect(suggestRollingLabel(90, "days")).toBe("90D");
  });

  it("labels a whole calendar year as the year, anything else as a short span", () => {
    expect(suggestFixedLabel("2024-01-01", "2024-12-31")).toBe("2024");
    expect(suggestFixedLabel("2024-04-15", "2025-04-15")).toBe("4/15–4/15/25");
  });
});

describe("resolveButton", () => {
  it("resolves each button type to an option", () => {
    expect(resolveButton({ type: "builtin", key: "last_month" }, today))
      .toEqual({ key: "last_month", label: "Aug", description: "Last complete month", from: "2026-08-01", to: "2026-08-31" });
    expect(resolveButton({ type: "rolling", id: "c1", label: "2Y", amount: 2, unit: "years" }, today))
      .toEqual({ key: "c1", label: "2Y", description: "Last 2 years", from: "2024-09-21", to: "2026-09-21" });
    expect(resolveButton({ type: "fixed", id: "c2", label: "FY24", from: "2023-10-01", to: "2024-09-30" }, today))
      .toEqual({ key: "c2", label: "FY24", description: "Oct 1, 2023 – Sep 30, 2024", from: "2023-10-01", to: "2024-09-30" });
  });
});

describe("parseTimeframeSettings", () => {
  it("uses the defaults when nothing is saved", () => {
    expect(parseTimeframeSettings(undefined)).toEqual({ settings: DEFAULT_TIMEFRAME_SETTINGS, isCustomized: false });
    expect(parseTimeframeSettings(null).isCustomized).toBe(false);
  });

  it("drops malformed and duplicate buttons", () => {
    const { settings } = parseTimeframeSettings({
      buttons: [
        { type: "builtin", key: "mtd" },
        { type: "builtin", key: "mtd" },
        { type: "builtin", key: "5y" },
        { type: "rolling", id: "c1", label: "2Y", amount: 2, unit: "years" },
        { type: "rolling", id: "c2", label: "bad", amount: 0, unit: "years" },
        { type: "fixed", id: "c3", label: "Backwards", from: "2025-01-01", to: "2024-01-01" },
        { type: "fixed", id: "c4", label: "", from: "2024-01-01", to: "2024-12-31" },
        "nonsense",
      ],
    });
    expect(settings.buttons.map((b) => (b.type === "builtin" ? b.key : b.id))).toEqual(["mtd", "c1"]);
  });

  it("falls back to the default buttons when every saved button is invalid", () => {
    expect(parseTimeframeSettings({ buttons: [{ type: "builtin", key: "nope" }] }))
      .toEqual({ settings: DEFAULT_TIMEFRAME_SETTINGS, isCustomized: false });
  });

  it("keeps per-page defaults only for known pages", () => {
    const { settings, isCustomized } = parseTimeframeSettings({ defaults: { net_worth: "mtd", bogus: "1y", tags: 5 } });
    expect(settings.defaults).toEqual({ net_worth: "mtd" });
    expect(settings.buttons).toEqual(DEFAULT_TIMEFRAME_SETTINGS.buttons);
    expect(isCustomized).toBe(true);
  });
});

describe("pageDefaultKey", () => {
  const row = (keys: string[], defaults: TimeframeSettings["defaults"] = {}): TimeframeSettings => ({
    buttons: keys.map((key) => ({ type: "builtin", key }) as TimeframeSettings["buttons"][number]),
    defaults,
  });

  it("uses each page's built-in default until the user picks one", () => {
    expect(pageDefaultKey(DEFAULT_TIMEFRAME_SETTINGS, "cashflow")).toBe("1y");
    expect(pageDefaultKey(DEFAULT_TIMEFRAME_SETTINGS, "investments")).toBe("all");
    expect(pageDefaultKey(row(["mtd", "1y", "all"], { investments: "mtd" }), "investments")).toBe("mtd");
  });

  it("falls back when the chosen button is gone: built-in default, then the first button", () => {
    expect(pageDefaultKey(row(["mtd", "1y"], { cashflow: "c_gone" }), "cashflow")).toBe("1y");
    expect(pageDefaultKey(row(["mtd", "ytd"], { cashflow: "c_gone" }), "cashflow")).toBe("mtd");
  });
});
