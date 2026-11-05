import { useEffect, useRef } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api, getToken } from "@/api/client";
import { queries } from "@/api/queries";
import { toast } from "@/components/ui/toast";
import { keys } from "@/api/keys";

// ── Shared debounce state (module-level so all hook instances share it) ───────

let pendingPatch: Record<string, unknown> = {};
let debounceTimer: ReturnType<typeof setTimeout> | null = null;

const DEBOUNCE_MS = 600;
const RETRY_DELAY_MS = 2000;

function flushPatch(attempt: number): Promise<void> {
  debounceTimer = null;
  if (Object.keys(pendingPatch).length === 0) return Promise.resolve();
  const toSend = pendingPatch;
  pendingPatch = {};
  // Promise.resolve guards the timer firing after test doubles reset
  // api.patch to return undefined — .catch on undefined throws.
  return Promise.resolve(api.patch("/preferences", { data: toSend })).then(() => {}, () => {
    // Re-queue on failure so the retry (or the next write) includes these
    // values; anything written since the failure wins over the stale copy.
    pendingPatch = { ...toSend, ...pendingPatch };
    if (attempt === 0) {
      if (!debounceTimer) debounceTimer = setTimeout(() => flushPatch(1), RETRY_DELAY_MS);
    } else {
      toast.error("Couldn't save your preferences — changes may not persist.");
    }
  });
}

// Sends any debounced write now, under the current token. Appearance is saved
// per household, so a household switch must flush first or a just-made change
// lands on the household being switched to.
export function flushPreferences(): Promise<void> {
  if (debounceTimer) clearTimeout(debounceTimer);
  // attempt 1: no delayed retry, which would fire under the next household's token.
  return flushPatch(1);
}

function schedulePatch(patch: Record<string, unknown>) {
  Object.assign(pendingPatch, patch);
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => flushPatch(0), DEBOUNCE_MS);
}

// Flush any debounced-but-unsent patch when the tab is hidden (backgrounded or
// being closed) — otherwise a quick theme change followed by closing the tab is
// silently lost. keepalive fetch (not sendBeacon: it can't carry the
// Authorization header) lets the request outlive the page.
function flushPendingOnHide() {
  if (document.visibilityState !== "hidden") return;
  if (debounceTimer) {
    clearTimeout(debounceTimer);
    debounceTimer = null;
  }
  if (Object.keys(pendingPatch).length === 0) return;
  const toSend = pendingPatch;
  pendingPatch = {};
  const token = getToken();
  void fetch("/api/v1/preferences", {
    method: "PATCH",
    keepalive: true,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ data: toSend }),
  }).catch(() => {
    // If the tab survives, re-queue for the next foreground flush.
    pendingPatch = { ...toSend, ...pendingPatch };
  });
}

if (typeof document !== "undefined") {
  document.addEventListener("visibilitychange", flushPendingOnHide);
}

// ── localStorage migration (runs once after first successful fetch) ───────────

const MIGRATION_KEY = "prefs-migrated-v1";

function migrateFromLocalStorage(remote: Record<string, unknown>): Record<string, unknown> | null {
  if (localStorage.getItem(MIGRATION_KEY)) return null;
  localStorage.setItem(MIGRATION_KEY, "1");

  // Only migrate if DB is empty — don't overwrite intentional DB values
  if (Object.keys(remote).length > 0) return null;

  const patch: Record<string, unknown> = {};

  const flat: [string, string][] = [
    ["theme",     "theme"],
    ["font",      "font"],
    ["font-size", "font_size"],
  ];
  for (const [lsKey, prefKey] of flat) {
    const v = localStorage.getItem(lsKey);
    if (v) patch[prefKey] = v;
  }

  const jsonKeys: [string, string][] = [
    ["txn-default-columns",              "transactions.columns"],
    ["txn-default-primary-sort",         "transactions.primary_sort"],
    ["txn-default-secondary-sort",       "transactions.secondary_sort"],
    ["txn-default-group-by",             "transactions.group_by"],
    ["txn-default-page-size",            "transactions.page_size"],
    ["txn-default-combine-merchant-desc","transactions.combine_merchant_desc"],
    ["txn-default-code-style-fallback",  "transactions.code_style_fallback"],
    ["txn-default-show-transfers",       "transactions.show_transfers"],
    ["txn-default-show-checkboxes",      "transactions.show_checkboxes"],
    ["market-column-prefs",              "market_column"],
  ];
  const txn: Record<string, unknown> = {};
  for (const [lsKey, dotPath] of jsonKeys) {
    try {
      const raw = localStorage.getItem(lsKey);
      if (!raw) continue;
      const val = JSON.parse(raw);
      if (dotPath.startsWith("transactions.")) {
        txn[dotPath.slice("transactions.".length)] = val;
      } else {
        patch[dotPath] = val;
      }
    } catch { /* ignore */ }
  }
  if (Object.keys(txn).length > 0) patch["transactions"] = txn;

  return Object.keys(patch).length > 0 ? patch : null;
}

// ── Hook ──────────────────────────────────────────────────────────────────────

export function usePreferences() {
  const qc = useQueryClient();
  const { data: remote = {}, isLoading } = useQuery(queries.preferences());
  const migrated = useRef(false);

  useEffect(() => {
    if (isLoading || migrated.current) return;
    migrated.current = true;
    const patch = migrateFromLocalStorage(remote);
    if (!patch) return;
    qc.setQueryData<Record<string, unknown>>(keys.preferences, (old = {}) => ({
      ...old,
      ...patch,
    }));
    schedulePatch(patch);
  }, [isLoading]); // eslint-disable-line react-hooks/exhaustive-deps

  function set(key: string, value: unknown) {
    qc.setQueryData<Record<string, unknown>>(keys.preferences, (old = {}) => ({
      ...old,
      [key]: value,
    }));
    schedulePatch({ [key]: value });
  }

  return { prefs: remote, set, isLoading };
}
