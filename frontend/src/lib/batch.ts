// ── Bounded-concurrency batch runner ──────────────────────────────────────────
// For actions that genuinely need one request per row (e.g. per-transfer
// confirms). Running them allSettled-style through a small worker pool keeps
// the browser from opening N sockets at once and — unlike Promise.all — never
// abandons rows behind the first failure.

export interface BatchResult<T> {
  /** Items whose task resolved. */
  succeeded: T[];
  /** Items whose task rejected. */
  failed: T[];
}

export async function runBatch<T>(
  items: readonly T[],
  task: (item: T) => Promise<unknown>,
  { concurrency = 5 }: { concurrency?: number } = {},
): Promise<BatchResult<T>> {
  const succeeded: T[] = [];
  const failed: T[] = [];
  let cursor = 0;

  async function worker() {
    while (cursor < items.length) {
      const item = items[cursor++];
      try {
        await task(item);
        succeeded.push(item);
      } catch {
        failed.push(item);
      }
    }
  }

  const workers = Array.from(
    { length: Math.max(1, Math.min(concurrency, items.length)) },
    () => worker(),
  );
  await Promise.all(workers);

  return { succeeded, failed };
}
