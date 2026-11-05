import { NavLink } from "react-router-dom";
import { LayoutDashboard, Wallet, ArrowLeftRight, Landmark, Settings } from "lucide-react";
import { cn } from "@/lib/utils";

const items = [
  { to: "/",             label: "Dashboard",   icon: LayoutDashboard, end: true },
  { to: "/cashflow",     label: "Cashflow",    icon: Wallet },
  { to: "/transactions", label: "Txns",        icon: ArrowLeftRight },
  { to: "/accounts",    label: "Accounts",    icon: Landmark },
  { to: "/settings",    label: "Settings",    icon: Settings },
];

export function MobileNav() {
  return (
    <nav className="fixed bottom-0 left-0 right-0 z-30 flex h-16 items-stretch border-t bg-card md:hidden">
      {items.map(({ to, label, icon: Icon, end }) => (
        <NavLink
          key={to}
          to={to}
          end={end}
          className={({ isActive }) =>
            cn(
              "flex flex-1 flex-col items-center justify-center gap-1 text-tiny font-medium transition-colors",
              isActive ? "text-primary" : "text-muted-foreground",
            )
          }
        >
          <Icon size={20} />
          {label}
        </NavLink>
      ))}
    </nav>
  );
}
