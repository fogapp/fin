import { describe, it, expect } from "vitest";
import { runBatch } from "./batch";

describe("runBatch", () => {
  it("runs every task and reports successes", async () => {
    const seen: number[] = [];
    const result = await runBatch([1, 2, 3], async (n) => { seen.push(n); });
    expect(seen.sort()).toEqual([1, 2, 3]);
    expect(result.succeeded.sort()).toEqual([1, 2, 3]);
    expect(result.failed).toEqual([]);
  });

  it("keeps going past failures and reports the failed items", async () => {
    const result = await runBatch(["a", "b", "c", "d"], async (id) => {
      if (id === "b" || id === "d") throw new Error(`nope ${id}`);
    });
    expect(result.succeeded.sort()).toEqual(["a", "c"]);
    expect(result.failed.sort()).toEqual(["b", "d"]);
  });

  it("never exceeds the concurrency bound", async () => {
    let inFlight = 0;
    let maxInFlight = 0;
    const items = Array.from({ length: 20 }, (_, i) => i);

    await runBatch(items, async () => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((r) => setTimeout(r, 1));
      inFlight -= 1;
    }, { concurrency: 5 });

    expect(maxInFlight).toBeLessThanOrEqual(5);
    expect(maxInFlight).toBeGreaterThan(1); // it does actually run in parallel
  });

  it("handles an empty item list", async () => {
    const result = await runBatch([], async () => {});
    expect(result.succeeded).toEqual([]);
    expect(result.failed).toEqual([]);
  });
});
