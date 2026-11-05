import { cn } from "@/lib/utils";

interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: "default" | "success" | "destructive" | "outline";
}

export function Badge({ className, variant = "default", ...props }: BadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
        {
          default: "bg-primary/10 text-primary",
          success: "bg-positive/15 text-positive",
          destructive: "bg-negative/15 text-negative",
          outline: "border border-border text-muted-foreground",
        }[variant],
        className,
      )}
      {...props}
    />
  );
}
