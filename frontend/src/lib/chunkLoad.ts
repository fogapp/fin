// ── Chunk-load failure detection ──────────────────────────────────────────────
// After a deploy, stale clients hold references to route chunks that no longer
// exist; the rejected dynamic import() is unrecoverable without fetching the
// new build. ErrorBoundary uses these helpers to reload once in that case —
// the sessionStorage flag stops a genuinely broken build from reload-looping.

export const CHUNK_RELOAD_FLAG = "fin-chunk-reload-attempted";

/** Browser messages for a failed dynamic import (Chrome / Firefox / Safari). */
export function isChunkLoadError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return /failed to fetch dynamically imported module|error loading dynamically imported module|importing a module script failed|failed to load module script/i.test(
    error.message,
  );
}
