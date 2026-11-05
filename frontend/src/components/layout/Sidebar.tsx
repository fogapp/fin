import { useState } from "react";
import { NavLink, useMatch } from "react-router-dom";
import type { LucideIcon } from "lucide-react";
import { LayoutDashboard, ArrowLeftRight, TrendingUp, BarChart2, Wallet, Store, Tags, Tag, Zap, Landmark, CreditCard, Receipt, Settings, PanelLeftClose, PanelLeftOpen } from "lucide-react";
import { cn } from "@/lib/utils";
import { FinMark } from "@/components/FinMark";
import { Tooltip, TooltipProvider } from "@/components/ui/tooltip";

const navGroups = [
  [
    { to: "/",           label: "Dashboard",   icon: LayoutDashboard, end: true },
    { to: "/investments",label: "Investments", icon: TrendingUp },
    { to: "/cashflow",   label: "Cashflow",    icon: Wallet },
    { to: "/market",     label: "Market",      icon: BarChart2 },
  ],
  [
    { to: "/transactions", label: "Transactions", icon: ArrowLeftRight },
    { to: "/merchants",    label: "Merchants",    icon: Store },
    { to: "/categories",   label: "Categories",   icon: Tags },
    { to: "/tags",         label: "Tags",         icon: Tag },
  ],
  [
    { to: "/accounts", label: "Accounts", icon: Landmark },
    { to: "/loans",    label: "Loans",    icon: CreditCard },
    { to: "/taxes",    label: "Taxes",    icon: Receipt },
    { to: "/workflows", label: "Workflows", icon: Zap },
  ],
];

export function Sidebar() {
  const [collapsed, setCollapsed] = useState(
    () => localStorage.getItem("sidebar-collapsed") === "true"
  );

  function toggle() {
    setCollapsed((c) => {
      localStorage.setItem("sidebar-collapsed", String(!c));
      return !c;
    });
  }

  return (
    <TooltipProvider>
    <aside data-sidebar className={cn("hidden md:flex h-screen flex-col border-r bg-card transition-[width] duration-200", collapsed ? "w-14" : "w-[220px]")}>
      {/* Header */}
      <div className={cn("flex h-14 items-center gap-2 border-b", collapsed ? "justify-center px-2" : "px-4")}>
        <FinMark className="size-7" />
        {!collapsed && <span className="flex-1 text-lg font-semibold tracking-tight text-foreground">Fin</span>}
      </div>

      {/* Nav */}
      <nav className="flex-1 overflow-y-auto p-2 pt-0">
        {navGroups.map((group, gi) => (
          <div key={gi}>
            {gi > 0 && <div className="my-4" />}
            <div className="space-y-0.5">
              {group.map((item) => (
                <SidebarLink key={item.to} {...item} collapsed={collapsed} />
              ))}
            </div>
          </div>
        ))}
      </nav>

      {/* Bottom */}
      <div className="space-y-0.5 border-t p-2">
        <SidebarLink to="/settings" label="Settings" icon={Settings} collapsed={collapsed} />
        <Tooltip content="Expand sidebar" side="right" disabled={!collapsed}>
          <button
            onClick={toggle}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            className={cn(
              "flex w-full items-center rounded-lg px-3 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-accent hover:text-foreground",
              collapsed ? "justify-center" : "gap-3",
            )}
          >
            {collapsed ? <PanelLeftOpen size={16} className="shrink-0" /> : <PanelLeftClose size={16} className="shrink-0" />}
            {!collapsed && "Collapse"}
          </button>
        </Tooltip>
      </div>
    </aside>
    </TooltipProvider>
  );
}

// NavLink's className must be a plain string here: when the tooltip is
// active (collapsed rail), Radix Trigger's asChild Slot merges props onto
// the child, and its className merge coerces a function-style className to
// its source string — every collapsed link lost its styling. Resolve the
// active state with useMatch instead of NavLink's callback form.
function SidebarLink({ to, label, icon: Icon, end, collapsed }: {
  to: string;
  label: string;
  icon: LucideIcon;
  end?: boolean;
  collapsed: boolean;
}) {
  const isActive = Boolean(useMatch({ path: to, end: end ?? false }));

  return (
    <Tooltip content={label} side="right" disabled={!collapsed}>
      <NavLink
        to={to}
        end={end}
        className={cn(
          "flex items-center rounded-lg px-3 py-2 text-sm font-medium transition-colors",
          collapsed ? "justify-center" : "gap-3",
          isActive
            ? "bg-primary/10 text-primary"
            : "text-muted-foreground hover:bg-accent hover:text-foreground",
        )}
      >
        <Icon size={16} className="shrink-0" />
        {!collapsed && label}
      </NavLink>
    </Tooltip>
  );
}
