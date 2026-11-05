// Tests for the market column-prefs hook. The task named this file
// useColumnPrefs.test.ts; the hook itself lives in useMarketColumnPrefs.ts
// (there is no src/hooks/useColumnPrefs.ts in the codebase).
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { createElement, type ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

vi.mock("@/api/client", () => ({
  api: {
    get: vi.fn(() => Promise.resolve({ data: {} })),
    post: vi.fn(() => Promise.resolve({})),
    patch: vi.fn(() => Promise.resolve({})),
    delete: vi.fn(() => Promise.resolve(undefined)),
  },
}));

import { useMarketColumnPrefs } from "./useMarketColumnPrefs";

const LS_KEY = "market-column-prefs";

const DEFAULTS = {
  primary: "ticker",
  subtitle: "name",
  value1: "price",
  value2: "day_change",
  sparkline: true,
};

function createWrapper(seedPreferences?: Record<string, unknown>) {
  const client = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: Infinity, staleTime: Infinity },
      mutations: { retry: false },
    },
  });
  if (seedPreferences) client.setQueryData(["preferences"], seedPreferences);
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client }, children);
  return { client, wrapper };
}

beforeEach(() => {
  localStorage.clear();
  // usePreferences runs a one-time localStorage → server migration; mark it as
  // already done so it doesn't interfere with these tests.
  localStorage.setItem("prefs-migrated-v1", "1");
});

describe("useMarketColumnPrefs — defaults", () => {
  it("returns the built-in defaults when nothing is stored anywhere", () => {
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useMarketColumnPrefs(), { wrapper });
    expect(result.current.prefs).toEqual(DEFAULTS);
  });

  it("falls back to defaults when localStorage holds invalid JSON", () => {
    localStorage.setItem(LS_KEY, "{not json");
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useMarketColumnPrefs(), { wrapper });
    expect(result.current.prefs).toEqual(DEFAULTS);
  });
});

describe("useMarketColumnPrefs — reading stored values", () => {
  it("reads prefs from localStorage when the server has none", () => {
    localStorage.setItem(LS_KEY, JSON.stringify({ primary: "name", value2: "none" }));
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useMarketColumnPrefs(), { wrapper });
    expect(result.current.prefs).toEqual({
      primary: "name",
      subtitle: "name",
      value1: "price",
      value2: "none",
      sparkline: true,
    });
  });

  it("merges a partial stored value with defaults", () => {
    localStorage.setItem(LS_KEY, JSON.stringify({ subtitle: "ticker" }));
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useMarketColumnPrefs(), { wrapper });
    expect(result.current.prefs).toEqual({ ...DEFAULTS, subtitle: "ticker" });
  });

  it("prefers server preferences over localStorage", () => {
    localStorage.setItem(LS_KEY, JSON.stringify({ primary: "ticker", value1: "none" }));
    const { wrapper } = createWrapper({ market_column: { primary: "name" } });
    const { result } = renderHook(() => useMarketColumnPrefs(), { wrapper });
    // Server value wins; unspecified keys come from DEFAULTS, not localStorage.
    expect(result.current.prefs).toEqual({ ...DEFAULTS, primary: "name" });
  });
});

describe("useMarketColumnPrefs — setPrefs", () => {
  it("updates the returned prefs and persists the merged object to localStorage", async () => {
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useMarketColumnPrefs(), { wrapper });

    act(() => result.current.setPrefs({ primary: "name" }));

    // localStorage is written synchronously…
    expect(JSON.parse(localStorage.getItem(LS_KEY)!)).toEqual({
      ...DEFAULTS,
      primary: "name",
    });
    // …and the hook re-renders with the new value (query notification is async)
    await waitFor(() => expect(result.current.prefs.primary).toBe("name"));
  });

  it("writes the pref into the shared preferences query cache", () => {
    const { client, wrapper } = createWrapper();
    const { result } = renderHook(() => useMarketColumnPrefs(), { wrapper });

    act(() => result.current.setPrefs({ value1: "market_value" }));

    const cached = client.getQueryData<Record<string, unknown>>(["preferences"]);
    expect(cached?.market_column).toEqual({ ...DEFAULTS, value1: "market_value" });
  });

  it("accumulates two setPrefs calls made synchronously in the same render cycle", async () => {
    const { wrapper } = createWrapper();
    const { result } = renderHook(() => useMarketColumnPrefs(), { wrapper });

    // No re-render between calls — the second merge must see the first update.
    act(() => {
      result.current.setPrefs({ primary: "name" });
      result.current.setPrefs({ subtitle: "none" });
    });

    await waitFor(() =>
      expect(result.current.prefs).toEqual({
        ...DEFAULTS,
        primary: "name",
        subtitle: "none",
      }),
    );
    expect(JSON.parse(localStorage.getItem(LS_KEY)!)).toEqual({
      ...DEFAULTS,
      primary: "name",
      subtitle: "none",
    });
  });
});
