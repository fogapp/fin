import { useEffect } from "react";

interface Options {
  onClose: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  onFirst?: () => void;
  onLast?: () => void;
}

/** Registers Escape / Arrow key handlers for a detail drawer panel. */
export function useDrawerKeyboard({ onClose, onPrev, onNext, onFirst, onLast }: Options) {
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      const tag = (e.target as HTMLElement)?.tagName;
      const isInput = tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT";
      if (e.key === "Escape" && !isInput) onClose();
      if (isInput) return;
      if (e.key === "ArrowUp")   { e.preventDefault(); if (e.metaKey || e.ctrlKey) onFirst?.(); else onPrev?.(); }
      if (e.key === "ArrowDown") { e.preventDefault(); if (e.metaKey || e.ctrlKey) onLast?.();  else onNext?.(); }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onClose, onPrev, onNext, onFirst, onLast]);
}
