import { useEffect, useState, type RefObject } from "react";

/**
 * The rendered height of `ref`'s element, kept current with a ResizeObserver.
 * `initial` covers the first paint before the observer reports (a sticky
 * header's usual height, so the layout doesn't jump).
 */
export function useElementHeight(ref: RefObject<HTMLElement | null>, initial = 0): number {
  const [height, setHeight] = useState(initial);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const obs = new ResizeObserver(() => setHeight(el.offsetHeight));
    obs.observe(el);
    return () => obs.disconnect();
  }, [ref]);
  return height;
}
