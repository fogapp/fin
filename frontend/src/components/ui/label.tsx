import { cn } from "@/lib/utils";

interface LabelProps extends React.LabelHTMLAttributes<HTMLLabelElement> {
  /** Appends the standard required marker (destructive asterisk). */
  required?: boolean;
}

export function Label({ className, required, children, ...props }: LabelProps) {
  return (
    <label className={cn("block text-xs font-medium text-muted-foreground", className)} {...props}>
      {children}
      {required && <span className="text-destructive"> *</span>}
    </label>
  );
}
