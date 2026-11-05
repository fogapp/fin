import { useState, useEffect, useRef } from "react";

export function useListSearch<T extends { id: string; name: string }>(items: T[]) {
  const [search, setSearch] = useState("");
  const [highlightedIndex, setHighlightedIndex] = useState<number | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const filtered = search.trim()
    ? items.filter((item) => item.name.toLowerCase().includes(search.toLowerCase()))
    : items;

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (
        e.key === "/" &&
        document.activeElement?.tagName !== "INPUT" &&
        document.activeElement?.tagName !== "TEXTAREA"
      ) {
        e.preventDefault();
        inputRef.current?.focus();
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  function handleChange(e: React.ChangeEvent<HTMLInputElement>) {
    setSearch(e.target.value);
    setHighlightedIndex(e.target.value.trim() ? 0 : null);
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>, onSelect: (item: T) => void) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setHighlightedIndex((i) => Math.min((i ?? -1) + 1, filtered.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setHighlightedIndex((i) => Math.max((i ?? 0) - 1, 0));
    } else if (e.key === "Enter") {
      const item = filtered[highlightedIndex ?? 0];
      if (item) {
        onSelect(item);
        setSearch("");
        setHighlightedIndex(null);
        inputRef.current?.blur();
      }
    } else if (e.key === "Escape") {
      setSearch("");
      setHighlightedIndex(null);
      inputRef.current?.blur();
    }
  }

  return { search, filtered, highlightedIndex, inputRef, handleChange, handleKeyDown };
}
