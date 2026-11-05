import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { HeaderActions } from "./HeaderActions";
import type { PageAction } from "./PageActionsMenu";

export type { PageAction };

interface PageHeaderProps {
  title: string;
  /** Heading level: 1 → `<h1 class="text-xl font-semibold">` (routed top-level
   * pages), 2 → `<h2 class="text-base font-semibold">` (sections/panes). */
  level?: 1 | 2;
  /** Muted one-liner under the title. */
  subtitle?: string;
  /** Back link on detail pages: explicit parent path + ArrowLeft icon. */
  back?: { to: string; label?: string };
  /** Sticks the header to the top of the scroll container (adds `sticky top-0 z-30` + `bg-card`). */
  sticky?: boolean;
  /** Page-level actions, collected into the pencil dropdown in the shared
   * header cluster. Prefer this over `children` for discrete action buttons. */
  actions?: PageAction[];
  /** Inline right-side controls (badges, steppers, primary submit buttons) —
   * stateful things that can't live in a dropdown. Render left of the shared
   * HeaderActions cluster. */
  children?: ReactNode;
}

export function PageHeader({ title, level = 2, subtitle, back, sticky = false, actions, children }: PageHeaderProps) {
  // z-30, not z-10: a sticky header is a stacking context, so everything
  // HeaderActions opens (the notification panel, the household switcher) is
  // trapped inside it however high its own z-index goes. Page content puts its
  // own sticky chrome at z-20 — the transactions table's filter bar, bulk bar
  // and thead — which outranked a z-10 header and painted over those panels.
  // The header is app chrome: it stays above page content, below the overlay
  // layer (dialogs, drawers, command palette, toasts at z-40+).
  const className =
    (sticky ? "sticky top-0 z-30 " : "") +
    "flex h-14 items-center justify-between border-b" +
    (sticky ? " bg-card" : "") +
    " px-6";

  return (
    <div className={className}>
      <div className="flex min-w-0 items-center gap-3">
        {back && (
          <Link
            to={back.to}
            aria-label={back.label ?? "Back"}
            className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <ArrowLeft size={16} />
          </Link>
        )}
        <div className="min-w-0">
          {level === 1
            ? <h1 className="truncate text-xl font-semibold">{title}</h1>
            : <h2 className="truncate text-base font-semibold">{title}</h2>}
          {subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}
        </div>
      </div>
      <div className="flex items-center gap-3">
        {children}
        <HeaderActions actions={actions} />
      </div>
    </div>
  );
}
