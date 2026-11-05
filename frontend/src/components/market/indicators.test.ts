import { describe, it, expect } from "vitest";
import { sma, ema, rsi, macd, bollinger, type TimeValue } from "./indicators";

function series(values: number[]): TimeValue[] {
  return values.map((value, i) => ({
    time: `2026-01-${String(i + 1).padStart(2, "0")}`,
    value,
  }));
}

describe("sma", () => {
  it("returns empty below the warm-up window", () => {
    expect(sma(series([1, 2]), 3)).toEqual([]);
  });

  it("averages a rolling window", () => {
    const out = sma(series([1, 2, 3, 4, 5]), 3);
    expect(out.map((p) => p.value)).toEqual([2, 3, 4]);
    expect(out[0].time).toBe("2026-01-03");
  });
});

describe("ema", () => {
  it("seeds with the SMA and smooths forward", () => {
    const out = ema(series([1, 2, 3, 4, 5]), 3);
    // Seed = SMA(1,2,3) = 2; k = 0.5 → 4·0.5 + 2·0.5 = 3, then 5·0.5 + 3·0.5 = 4.
    expect(out.map((p) => p.value)).toEqual([2, 3, 4]);
  });

  it("converges toward a constant series", () => {
    const out = ema(series(Array(50).fill(7)), 10);
    expect(out.at(-1)!.value).toBeCloseTo(7, 10);
  });
});

describe("rsi", () => {
  it("is 100 for a monotonic rise", () => {
    const out = rsi(series([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]), 14);
    expect(out.at(-1)!.value).toBe(100);
  });

  it("is 0 for a monotonic fall", () => {
    const out = rsi(series([16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]), 14);
    expect(out.at(-1)!.value).toBe(0);
  });

  it("is ~50 for an alternating series", () => {
    const values = Array.from({ length: 30 }, (_, i) => (i % 2 === 0 ? 10 : 11));
    const out = rsi(series(values), 14);
    expect(out.at(-1)!.value).toBeGreaterThan(35);
    expect(out.at(-1)!.value).toBeLessThan(65);
  });

  it("stays within 0..100", () => {
    const values = Array.from({ length: 60 }, (_, i) => 100 + Math.sin(i) * 20);
    for (const p of rsi(series(values))) {
      expect(p.value).toBeGreaterThanOrEqual(0);
      expect(p.value).toBeLessThanOrEqual(100);
    }
  });
});

describe("macd", () => {
  it("returns empty when the slow window never fills", () => {
    expect(macd(series([1, 2, 3]))).toEqual([]);
  });

  it("histogram equals macd minus signal", () => {
    const values = Array.from({ length: 80 }, (_, i) => 100 + i + Math.sin(i / 3) * 5);
    for (const p of macd(series(values))) {
      expect(p.histogram).toBeCloseTo(p.macd - p.signal, 10);
    }
  });

  it("is ~zero for a flat series", () => {
    const out = macd(series(Array(80).fill(50)));
    expect(out.at(-1)!.macd).toBeCloseTo(0, 8);
  });
});

describe("bollinger", () => {
  it("collapses to the mean for a constant series", () => {
    const out = bollinger(series(Array(25).fill(10)), 20, 2);
    const p = out.at(-1)!;
    expect(p.upper).toBe(10);
    expect(p.middle).toBe(10);
    expect(p.lower).toBe(10);
  });

  it("bands straddle the middle symmetrically", () => {
    const values = Array.from({ length: 40 }, (_, i) => 100 + Math.sin(i) * 10);
    for (const p of bollinger(series(values))) {
      expect(p.upper - p.middle).toBeCloseTo(p.middle - p.lower, 10);
      expect(p.upper).toBeGreaterThanOrEqual(p.lower);
    }
  });
});
