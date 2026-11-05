import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

vi.mock("@/api/client", async () => {
  const actual = await vi.importActual<typeof import("@/api/client")>("@/api/client");
  return {
    ...actual,
    api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), patch: vi.fn(), delete: vi.fn() },
  };
});

import { api } from "@/api/client";
import { usePreferences } from "./usePreferences";

const apiMock = vi.mocked(api);

// The hook batches writes behind a module-level 600ms debounce and retries once
// after 2s, so these tests drive fake timers rather than waiting in real time.
const DEBOUNCE_MS = 600;
const RETRY_DELAY_MS = 2000;

/** One client per test — recreating it per render would drop the cache the
 *  hook writes to optimistically. */
function makeWrapper() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: Infinity }, mutations: { retry: false } },
  });
  return function Wrapper({ children }: { children: React.ReactNode }) {
    return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  };
}

async function renderPrefs(remote: Record<string, unknown> = {}) {
  // GET /preferences answers { data: {...} }; the query unwraps `.data`.
  apiMock.get.mockResolvedValue({ data: remote } as never);
  const hook = renderHook(() => usePreferences(), { wrapper: makeWrapper() });
  await waitFor(() => expect(hook.result.current.isLoading).toBe(false));
  return hook;
}

beforeEach(() => {
  vi.clearAllMocks();
  localStorage.clear();
  // Skip the one-time localStorage → server migration so it can't add its own
  // PATCH to the assertions below.
  localStorage.setItem("prefs-migrated-v1", "1");
  apiMock.patch.mockResolvedValue({} as never);
  vi.useFakeTimers({ shouldAdvanceTime: true });
});

afterEach(() => {
  vi.runOnlyPendingTimers();
  vi.useRealTimers();
});

describe("usePreferences → PATCH /preferences", () => {
  it("sends a changed preference after the debounce window", async () => {
    const { result } = await renderPrefs();

    act(() => result.current.set("theme", "copper"));
    expect(apiMock.patch).not.toHaveBeenCalled();

    await act(async () => { vi.advanceTimersByTime(DEBOUNCE_MS); });

    expect(apiMock.patch).toHaveBeenCalledWith("/preferences", { data: { theme: "copper" } });
  });

  it("coalesces rapid writes into a single PATCH", async () => {
    const { result } = await renderPrefs();

    act(() => {
      result.current.set("theme", "copper");
      result.current.set("font", "nunito");
      result.current.set("font_size", "sm");
    });

    await act(async () => { vi.advanceTimersByTime(DEBOUNCE_MS); });

    expect(apiMock.patch).toHaveBeenCalledTimes(1);
    expect(apiMock.patch).toHaveBeenCalledWith("/preferences", {
      data: { theme: "copper", font: "nunito", font_size: "sm" },
    });
  });

  it("keeps the last value when the same key is written twice", async () => {
    const { result } = await renderPrefs();

    act(() => {
      result.current.set("theme", "copper");
      result.current.set("theme", "slate");
    });

    await act(async () => { vi.advanceTimersByTime(DEBOUNCE_MS); });

    expect(apiMock.patch).toHaveBeenCalledWith("/preferences", { data: { theme: "slate" } });
  });

  it("updates the cached value immediately, before the request goes out", async () => {
    const { result } = await renderPrefs({ theme: "slate" });

    await act(async () => { result.current.set("theme", "copper"); });

    await waitFor(() => expect(result.current.prefs).toMatchObject({ theme: "copper" }));
    expect(apiMock.patch).not.toHaveBeenCalled();
  });

  it("re-sends the failed values on the retry pass", async () => {
    apiMock.patch.mockRejectedValueOnce(new Error("Internal server error"));
    const { result } = await renderPrefs();

    act(() => result.current.set("theme", "copper"));
    await act(async () => { vi.advanceTimersByTime(DEBOUNCE_MS); });
    expect(apiMock.patch).toHaveBeenCalledTimes(1);

    await act(async () => { vi.advanceTimersByTime(RETRY_DELAY_MS); });

    expect(apiMock.patch).toHaveBeenCalledTimes(2);
    expect(apiMock.patch).toHaveBeenLastCalledWith("/preferences", { data: { theme: "copper" } });
  });

  it("lets a newer write win over the value that failed", async () => {
    apiMock.patch.mockRejectedValueOnce(new Error("boom"));
    const { result } = await renderPrefs();

    act(() => result.current.set("theme", "copper"));
    await act(async () => { vi.advanceTimersByTime(DEBOUNCE_MS); });

    act(() => result.current.set("theme", "slate"));
    await act(async () => { vi.advanceTimersByTime(RETRY_DELAY_MS); });

    expect(apiMock.patch).toHaveBeenLastCalledWith("/preferences", { data: { theme: "slate" } });
  });

  it("does not PATCH when nothing was written", async () => {
    await renderPrefs({ theme: "slate" });

    await act(async () => { vi.advanceTimersByTime(DEBOUNCE_MS * 3); });

    expect(apiMock.patch).not.toHaveBeenCalled();
  });
});
