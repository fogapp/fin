import * as RadixTooltip from "@radix-ui/react-tooltip";
import { cn } from "@/lib/utils";

// Radix-based tooltip. Wrap a related cluster (e.g. the collapsed sidebar) in
// one TooltipProvider so moving between triggers skips the open delay.

export function TooltipProvider({ children, delayDuration = 150 }: {
  children: React.ReactNode;
  delayDuration?: number;
}) {
  return (
    <RadixTooltip.Provider delayDuration={delayDuration} skipDelayDuration={300}>
      {children}
    </RadixTooltip.Provider>
  );
}

export function Tooltip({ content, side = "top", disabled = false, className, children }: {
  content: React.ReactNode;
  side?: "top" | "right" | "bottom" | "left";
  /** Render the child without a tooltip (e.g. expanded sidebar rows). */
  disabled?: boolean;
  className?: string;
  children: React.ReactNode;
}) {
  if (disabled) return <>{children}</>;

  return (
    <RadixTooltip.Root>
      <RadixTooltip.Trigger asChild>{children}</RadixTooltip.Trigger>
      <RadixTooltip.Portal>
        <RadixTooltip.Content
          side={side}
          sideOffset={6}
          className={cn(
            "z-50 rounded-md border bg-card px-2 py-1 text-xs font-medium text-card-foreground shadow-md",
            className,
          )}
        >
          {content}
        </RadixTooltip.Content>
      </RadixTooltip.Portal>
    </RadixTooltip.Root>
  );
}
