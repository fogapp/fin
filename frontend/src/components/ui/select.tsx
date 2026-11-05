import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

// Native select styled to match Input (h-9, rounded-lg, focus ring), with the
// OS arrow replaced by a lucide chevron. Pass <option> elements as children.
interface SelectProps extends React.ComponentProps<"select"> {
  /** Class for the positioning wrapper (width/layout); `className` styles the select itself. */
  wrapperClassName?: string;
}

export function Select({ className, wrapperClassName, children, ...props }: SelectProps) {
  return (
    <div className={cn("relative", wrapperClassName)}>
      <select
        className={cn(
          "h-9 w-full appearance-none rounded-lg border border-input bg-background pl-3 pr-8 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:cursor-not-allowed disabled:opacity-50",
          className,
        )}
        {...props}
      >
        {children}
      </select>
      <ChevronDown size={13} className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
    </div>
  );
}
