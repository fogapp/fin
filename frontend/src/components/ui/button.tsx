import { cn } from "@/lib/utils";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "default" | "outline" | "ghost" | "destructive";
  size?: "xs" | "sm" | "md" | "lg" | "icon" | "icon-sm";
}

export function Button({ className, variant = "default", size = "md", ...props }: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-lg font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:pointer-events-none disabled:opacity-50",
        {
          default: "bg-primary text-primary-foreground hover:bg-primary/90",
          outline: "border border-border bg-background hover:bg-accent",
          ghost: "hover:bg-accent hover:text-accent-foreground",
          destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
        }[variant],
        {
          xs: "h-7 px-2.5 text-xs",
          sm: "h-8 px-3 text-xs",
          md: "h-9 px-4 text-sm",
          lg: "h-10 px-6 text-sm",
          icon: "h-9 w-9",
          "icon-sm": "h-7 w-7",
        }[size],
        className,
      )}
      {...props}
    />
  );
}
