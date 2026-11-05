import { ArrowUpRight } from "lucide-react";
import { cn } from "@/lib/utils";

// ── Section rail ──────────────────────────────────────────────────────────────
// The shared vertical section nav used by Cashflow, Investments, and Settings:
// a labeled rail on desktop (w-48, right border) that collapses to horizontal
// scrolling tabs on mobile. Extracted from the previously-triplicated inline
// implementation — change it here, not per page.

export interface RailSection {
  id: string;
  label: string;
  /** Attention count rendered as a destructive pill after the label (e.g. open issues). */
  count?: number;
  /** Marks an item that navigates away from the rail's own page (renders a link-out arrow). */
  external?: boolean;
}

export function SectionRailNav({ title, sections, active, onSelect, children }: {
  /** Rail heading shown in the desktop `h-14` slot. */
  title: string;
  sections: RailSection[];
  active: string;
  onSelect: (id: string) => void;
  /** Optional extra rail content rendered under the nav (desktop only). */
  children?: React.ReactNode;
}) {
  return (
    <div className="flex w-full shrink-0 flex-row overflow-x-auto border-b bg-card md:w-48 md:flex-col md:border-b-0 md:border-r">
      <div className="hidden h-14 items-center border-b px-4 md:flex">
        <p className="text-sm font-medium">{title}</p>
      </div>
      <nav className="flex flex-row p-1 md:flex-1 md:flex-col md:p-2">
        {sections.map((s) => (
          <button
            key={s.id}
            onClick={() => onSelect(s.id)}
            className={cn(
              "flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary md:w-full md:text-left",
              active === s.id ? "bg-primary/8 text-primary" : "text-muted-foreground",
            )}
          >
            {s.label}
            {s.count != null && s.count > 0 && (
              <span className="ml-auto rounded-full bg-destructive px-1.5 py-0.5 text-tiny font-medium leading-none text-destructive-foreground">
                {s.count}
              </span>
            )}
            {s.external && <ArrowUpRight size={13} className="ml-auto text-muted-foreground" />}
          </button>
        ))}
      </nav>
      {children}
    </div>
  );
}
