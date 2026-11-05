import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, ChevronDown, Plus } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { useAuth } from "@/hooks/useAuth";
import { flushPreferences } from "@/hooks/usePreferences";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { Household } from "@/api/types";

interface SwitchResponse {
  token: string;
  household: { id: string; name: string; role: string };
}

export function HouseholdSwitcher() {
  const { data: households = [] } = useQuery(queries.households());
  const { login } = useAuth();
  const qc = useQueryClient();
  const navigate = useNavigate();

  const active   = households.find((h) => h.active);
  const inactive = households.filter((h) => !h.active);
  const [busy, setBusy] = useState(false);

  // Single-household users don't see the switcher at all (matches the
  // "Only when the user has 2+ households" preference).
  if (households.length < 2 || !active) return null;

  async function switchTo(household: Household) {
    setBusy(true);
    try {
      await flushPreferences();
      const res = await api.post<SwitchResponse>("/auth/switch_household", { household_id: household.id });
      login(res.token);
      // Drop every cached query — they were fetched under the old household's
      // scope and would surface stale data otherwise.
      qc.clear();
    } finally {
      setBusy(false);
    }
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          disabled={busy}
          className="flex items-center gap-1.5 rounded-md border border-input bg-background px-2.5 py-1 text-sm font-medium hover:bg-accent disabled:opacity-50"
        >
          <span className="max-w-[150px] truncate">{active.name}</span>
          <ChevronDown size={14} className="text-muted-foreground" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-64">
        <DropdownMenuLabel className="text-tiny font-semibold uppercase tracking-wider">
          Switch household
        </DropdownMenuLabel>
        <HouseholdRow household={active} isActive />
        {inactive.map((h) => (
          <HouseholdRow key={h.id} household={h} onSelect={() => switchTo(h)} />
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuItem
          className="text-muted-foreground"
          onSelect={() => navigate("/settings#topic=household")}
        >
          <Plus size={14} />
          Create new household
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function HouseholdRow({ household, isActive, onSelect }: {
  household: Household; isActive?: boolean; onSelect?: () => void;
}) {
  return (
    <DropdownMenuItem
      onSelect={onSelect}
      className={`justify-between ${isActive ? "text-foreground" : "text-muted-foreground"}`}
    >
      <div className="min-w-0">
        <p className="truncate font-medium">{household.name}</p>
        <p className="text-caption uppercase tracking-wider text-muted-foreground">{household.role}</p>
      </div>
      {isActive && <Check size={14} className="text-primary" />}
    </DropdownMenuItem>
  );
}
