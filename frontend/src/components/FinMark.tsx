import { cn } from "@/lib/utils";

/** The Fin logomark (the fin). Decorative: pair it with the "Fin" wordmark. */
export function FinMark({ className }: { className?: string }) {
  return <img src="/fin-mark.svg" alt="" aria-hidden className={cn("size-6 shrink-0 select-none", className)} draggable={false} />;
}
