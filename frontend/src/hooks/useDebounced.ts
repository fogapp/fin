import { useEffect, useState } from "react";

/** Returns `value`, delayed by `ms` — resets the timer on every change so
 * only the value after typing settles is committed. */
export function useDebounced<T>(value: T, ms: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return debounced;
}
