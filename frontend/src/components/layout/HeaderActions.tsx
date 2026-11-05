import { useQuery } from "@tanstack/react-query";
import { Search } from "lucide-react";
import { queries } from "@/api/queries";
import { useSearchPalette } from "@/hooks/useSearchPalette";
import { HouseholdSwitcher } from "./HouseholdSwitcher";
import { NotificationBell } from "./NotificationBell";
import { AvatarMenu } from "./AvatarMenu";
import { PageActionsMenu } from "./PageActionsMenu";
import type { PageAction } from "./PageActionsMenu";

/** Right-edge cluster for every page's top header bar, in fixed order:
 *  the page-actions pencil menu (when the page has actions), the household
 *  switcher (only with 2+ households), the notification bell, the search
 *  icon, and the user avatar. Lives inside each page header instead of a
 *  dedicated shell strip. */
export function HeaderActions({ actions = [] }: { actions?: PageAction[] }) {
  const { data: households = [] } = useQuery(queries.households());
  const { openSearch } = useSearchPalette();

  return (
    <div className="flex items-center gap-2">
      <PageActionsMenu actions={actions} />
      {households.length >= 2 && <HouseholdSwitcher />}
      <NotificationBell />
      <button
        onClick={openSearch}
        aria-label="Search"
        title="Search (⌘K)"
        className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
      >
        <Search size={16} />
      </button>
      <AvatarMenu />
    </div>
  );
}
