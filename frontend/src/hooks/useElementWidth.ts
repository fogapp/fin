import { useEffect, useState, type RefObject } from "react";

/**
 * The rendered width of `ref`'s element, kept current with a ResizeObserver —
 * for SVG charts that draw in real pixels instead of a stretched viewBox.
 * `initial` covers the first paint (and jsdom, which never reports).
 */
export function useElementWidth(ref: RefObject<HTMLElement | null>, initial = 0): number {
  const [width, setWidth] = useState(initial);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const obs = new ResizeObserver(() => { if (el.clientWidth > 0) setWidth(el.clientWidth); });
    obs.observe(el);
    return () => obs.disconnect();
  }, [ref]);
  return width;
}
