import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

// ── Empty state ───────────────────────────────────────────────────────────────
// Standard empty placeholder. Copy convention:
//   truly empty  → "No loans yet." + a CTA when the user can add one
//   filtered out → "No holdings match the current filters." (no CTA)

export function EmptyState({ icon: Icon, title, description, action, className }: {
  icon?: LucideIcon;
  title: string;
  description?: string;
  /** Optional CTA, e.g. a <Button> that opens the create flow. */
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col items-center justify-center gap-2 px-6 py-12 text-center", className)}>
      {Icon && <Icon size={20} className="text-muted-foreground/60" />}
      <p className="text-sm font-medium">{title}</p>
      {description && <p className="max-w-sm text-xs text-muted-foreground">{description}</p>}
      {action && <div className="pt-2">{action}</div>}
    </div>
  );
}
