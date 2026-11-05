import { describe, it, expect, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import {
  chartModeFor, seriesColor, assignSeriesColors, activityBucketColor, useChartTheme,
  LIGHT_SERIES, DARK_SERIES, ACTIVITY_BUCKET_ORDER,
} from "./theme";

describe("chartModeFor", () => {
  it("treats dark theme ids as dark and everything else (incl. split themes) as light", () => {
    for (const id of ["dark", "midnight", "dusk", "slate", "ember"]) {
      expect(chartModeFor(id)).toBe("dark");
    }
    for (const id of [null, "", "light", "sand", "copper", "eclipse", "sage"]) {
      expect(chartModeFor(id)).toBe("light");
    }
  });
});

describe("seriesColor", () => {
  it("indexes the fixed palette order and never cycles past slot 8", () => {
    function theme(mode: "light" | "dark") {
      return { mode, series: mode === "light" ? LIGHT_SERIES : DARK_SERIES, neutral: "#898781" } as never;
    }
    expect(seriesColor(theme("light"), 0)).toBe("#2a78d6");
    expect(seriesColor(theme("light"), 7)).toBe("#eb6834");
    // A 9th series folds into "Other" — neutral, not a recycled hue.
    expect(seriesColor(theme("light"), 8)).toBe("#898781");
    expect(seriesColor(theme("dark"), 0)).toBe("#3987e5");
    expect(seriesColor(theme("dark"), 99)).toBe("#898781");
  });
});

describe("assignSeriesColors", () => {
  const theme = { series: LIGHT_SERIES, neutral: "#898781" } as never;

  it("assigns slots by fixed order of first appearance, deduplicated", () => {
    const map = assignSeriesColors(["Groceries", "Dining", "Groceries", "Travel"], theme);
    expect(map.get("Groceries")).toBe(LIGHT_SERIES[0]);
    expect(map.get("Dining")).toBe(LIGHT_SERIES[1]);
    expect(map.get("Travel")).toBe(LIGHT_SERIES[2]);
    expect(map.size).toBe(3);
  });

  it("never cycles: the 9th+ entity gets neutral; unknown lookups fall to neutral", () => {
    const names = Array.from({ length: 10 }, (_, i) => `e${i}`);
    const map = assignSeriesColors(names, theme);
    expect(map.get("e7")).toBe(LIGHT_SERIES[7]);
    expect(map.get("e8")).toBe("#898781");
    expect(map.get("e9")).toBe("#898781");
    // Entities that never got a slot (e.g. a list row not in the chart)
    expect(map.get("not-in-chart") ?? "#898781").toBe("#898781");
  });
});

describe("activityBucketColor", () => {
  it("assigns slots by the fixed bucket order, unknown buckets get neutral", () => {
    const theme = { series: LIGHT_SERIES, neutral: "#898781" } as never;
    ACTIVITY_BUCKET_ORDER.forEach((name, i) => {
      expect(activityBucketColor(theme, name)).toBe(LIGHT_SERIES[i]);
    });
    expect(activityBucketColor(theme, "Mystery")).toBe("#898781");
  });
});

function ModeProbe() {
  const theme = useChartTheme();
  return <output data-testid="mode">{theme.mode}</output>;
}

describe("useChartTheme", () => {
  afterEach(() => document.documentElement.removeAttribute("data-theme"));

  it("follows [data-theme] on the root element live", async () => {
    document.documentElement.setAttribute("data-theme", "copper");
    render(<ModeProbe />);
    expect(screen.getByTestId("mode")).toHaveTextContent("light");

    document.documentElement.setAttribute("data-theme", "midnight");
    await waitFor(() => expect(screen.getByTestId("mode")).toHaveTextContent("dark"));

    document.documentElement.setAttribute("data-theme", "");
    await waitFor(() => expect(screen.getByTestId("mode")).toHaveTextContent("light"));
  });
});
