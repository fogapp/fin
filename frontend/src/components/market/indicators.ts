/**
 * Technical-indicator math for the advanced price chart. Pure functions over
 * (time, value) points — no chart-library coupling, unit-tested in isolation.
 *
 * All functions preserve input ordering (ascending time) and only emit
 * points once the indicator has a full warm-up window, so charts never show
 * a partially-seeded average.
 */

export interface TimeValue {
  time: string;
  value: number;
}

export interface MacdPoint {
  time: string;
  macd: number;
  signal: number;
  histogram: number;
}

export interface BollingerPoint {
  time: string;
  upper: number;
  middle: number;
  lower: number;
}

/** Simple moving average over `period` points. */
export function sma(data: TimeValue[], period: number): TimeValue[] {
  if (period <= 0 || data.length < period) return [];
  const out: TimeValue[] = [];
  let sum = 0;
  for (let i = 0; i < data.length; i++) {
    sum += data[i].value;
    if (i >= period) sum -= data[i - period].value;
    if (i >= period - 1) out.push({ time: data[i].time, value: sum / period });
  }
  return out;
}

/** Exponential moving average, seeded with the SMA of the first window. */
export function ema(data: TimeValue[], period: number): TimeValue[] {
  if (period <= 0 || data.length < period) return [];
  const k = 2 / (period + 1);
  const out: TimeValue[] = [];
  let prev = data.slice(0, period).reduce((s, d) => s + d.value, 0) / period;
  out.push({ time: data[period - 1].time, value: prev });
  for (let i = period; i < data.length; i++) {
    prev = data[i].value * k + prev * (1 - k);
    out.push({ time: data[i].time, value: prev });
  }
  return out;
}

/** Relative Strength Index (Wilder smoothing), 0–100. */
export function rsi(data: TimeValue[], period = 14): TimeValue[] {
  if (data.length <= period) return [];
  const out: TimeValue[] = [];
  let avgGain = 0;
  let avgLoss = 0;
  for (let i = 1; i <= period; i++) {
    const change = data[i].value - data[i - 1].value;
    if (change > 0) avgGain += change;
    else avgLoss -= change;
  }
  avgGain /= period;
  avgLoss /= period;
  out.push({ time: data[period].time, value: toRsi(avgGain, avgLoss) });
  for (let i = period + 1; i < data.length; i++) {
    const change = data[i].value - data[i - 1].value;
    avgGain = (avgGain * (period - 1) + Math.max(change, 0)) / period;
    avgLoss = (avgLoss * (period - 1) + Math.max(-change, 0)) / period;
    out.push({ time: data[i].time, value: toRsi(avgGain, avgLoss) });
  }
  return out;
}

function toRsi(avgGain: number, avgLoss: number): number {
  if (avgLoss === 0) return avgGain === 0 ? 50 : 100;
  return 100 - 100 / (1 + avgGain / avgLoss);
}

/** MACD (12/26 EMA difference) with a 9-period signal line. */
export function macd(data: TimeValue[], fast = 12, slow = 26, signalPeriod = 9): MacdPoint[] {
  const fastEma = ema(data, fast);
  const slowEma = ema(data, slow);
  if (slowEma.length === 0) return [];

  const fastByTime = new Map(fastEma.map((p) => [p.time, p.value]));
  const macdLine: TimeValue[] = [];
  for (const p of slowEma) {
    const f = fastByTime.get(p.time);
    if (f !== undefined) macdLine.push({ time: p.time, value: f - p.value });
  }

  const signalLine = ema(macdLine, signalPeriod);
  const signalByTime = new Map(signalLine.map((p) => [p.time, p.value]));
  return macdLine
    .filter((p) => signalByTime.has(p.time))
    .map((p) => {
      const signal = signalByTime.get(p.time)!;
      return { time: p.time, macd: p.value, signal, histogram: p.value - signal };
    });
}

/** Bollinger bands: SMA ± `mult` standard deviations (population σ). */
export function bollinger(data: TimeValue[], period = 20, mult = 2): BollingerPoint[] {
  if (data.length < period) return [];
  const out: BollingerPoint[] = [];
  for (let i = period - 1; i < data.length; i++) {
    const window = data.slice(i - period + 1, i + 1);
    const mean = window.reduce((s, d) => s + d.value, 0) / period;
    const variance = window.reduce((s, d) => s + (d.value - mean) ** 2, 0) / period;
    const sd = Math.sqrt(variance);
    out.push({ time: data[i].time, upper: mean + mult * sd, middle: mean, lower: mean - mult * sd });
  }
  return out;
}
