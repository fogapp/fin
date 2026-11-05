import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Settings, LogOut } from "lucide-react";
import { queries } from "@/api/queries";
import { useAuth } from "@/hooks/useAuth";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";

function initialsOf(name: string | null, email: string): string {
  const source = name?.trim() || email;
  const parts = source.split(/[\s@._-]+/).filter(Boolean);
  const first = parts[0]?.[0] ?? "?";
  const second = parts.length > 1 ? parts[1]?.[0] : source[1];
  return (first + (second ?? "")).toUpperCase();
}

/** The user avatar at the far right of every page header: initials chip
 *  opening a menu with Settings and Sign out. */
export function AvatarMenu() {
  const navigate = useNavigate();
  const { logout } = useAuth();
  const { data: me } = useQuery(queries.me());

  const name = me?.user?.name ?? null;
  const email = me?.user?.email ?? "";

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          aria-label="Account menu"
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary transition-colors hover:bg-primary/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          {me?.user ? initialsOf(name, email) : "…"}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuLabel>
          <span className="block truncate text-foreground">{name || email || "Account"}</span>
          {name && email && <span className="block truncate font-normal">{email}</span>}
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={() => navigate("/settings")}>
          <Settings size={14} className="text-muted-foreground" />
          Settings
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={logout}>
          <LogOut size={14} className="text-muted-foreground" />
          Sign out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
