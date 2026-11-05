import { useEffect } from "react";

/**
 * Post-sync polling: once a background sync is queued, refetch on an
 * escalating schedule and stop after `timeoutMs` — server-side syncs vary in
 * duration, so this bounds the refresh churn instead of polling forever.
 * `onStop` is where the caller clears its syncing flag.
 */
export function useSyncPolling(active: boolean, { delays, timeoutMs, onPoll, onStop }: {
  delays: number[];
  timeoutMs: number;
  onPoll: () => void;
  onStop: () => void;
}) {
  useEffect(() => {
    if (!active) return;
    const timers = delays.map((ms) => setTimeout(() => onPoll(), ms));
    const done = setTimeout(() => onStop(), timeoutMs);
    return () => { timers.forEach(clearTimeout); clearTimeout(done); };
  }, [active]); // eslint-disable-line react-hooks/exhaustive-deps
}
