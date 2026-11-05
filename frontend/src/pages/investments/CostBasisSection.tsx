import { Fragment, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronRight } from "lucide-react";
import { queries } from "@/api/queries";
import { InvestmentLotsEditor } from "@/components/InvestmentLotsEditor";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { StatRibbon } from "@/components/StatRibbon";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Tabs } from "@/components/ui/tabs";
import { holdingDisplayName, holdingSubtitle } from "@/components/holdings/types";
import { formatCurrency, cn, moneyColor } from "@/lib/utils";
import { SectionLoading } from "./SectionLayout";
import type { CostBasisLot, CostBasisPosition } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

type Filter = "all" | "complete" | "gaps";

function StatusBadge({ status }: { status: CostBasisPosition["status"] }) {
  if (status === "complete") {
    return <Badge variant="success">Complete</Badge>;
  }
  if (status === "partial") {
    return <Badge className="bg-warning/15 text-warning">Partial</Badge>;
  }
  return <Badge className="bg-muted text-muted-foreground">Unknown</Badge>;
}

function CoverageCell({ position }: { position: CostBasisPosition }) {
  const { current_quantity, net_quantity, status } = position;
  if (status === "unknown" || current_quantity < 0.0001) return <span className="text-muted-foreground">—</span>;
  const covered = Math.min(net_quantity, current_quantity);
  const pct = current_quantity > 0 ? Math.round((covered / current_quantity) * 100) : 0;
  const clamped = Math.max(0, Math.min(100, pct));
  return (
    <div className="flex items-center gap-2 justify-end">
      <div className="h-1.5 w-16 rounded-full bg-muted overflow-hidden">
        <div
          className={cn("h-full rounded-full", clamped >= 100 ? "bg-positive" : clamped > 50 ? "bg-warning" : "bg-negative")}
          style={{ width: `${clamped}%` }}
        />
      </div>
      <span className="w-10 text-right tabular-nums">{clamped}%</span>
    </div>
  );
}

export function CostBasisSection() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { data, isLoading, refetch } = useQuery(queries.costBasis());
  const { data: accounts = [] } = useQuery(queries.accounts());
  const [filter, setFilter] = useState<Filter>("all");
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  // Local lot overrides so the expanded editor stays responsive without a full refetch
  const [lotOverrides, setLotOverrides] = useState<Map<string, CostBasisLot[]>>(new Map());

  if (isLoading) return <SectionLoading />;
  if (!data) return <ErrorState title="Failed to load cost basis" onRetry={() => refetch()} />;

  const { summary, positions } = data;

  const filtered = positions.filter((p) => {
    if (filter === "complete") return p.status === "complete";
    if (filter === "gaps") return p.status === "partial" || p.status === "unknown";
    return true;
  });

  const filterTabs = [
    { value: "all" as const,      label: "All",      count: summary.total_positions },
    { value: "complete" as const, label: "Complete", count: summary.complete },
    { value: "gaps" as const,     label: "Gaps",     count: summary.partial + summary.unknown },
  ];

  function toggleExpand(securityId: string) {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(securityId)) next.delete(securityId);
      else next.add(securityId);
      return next;
    });
  }

  function handleLotsChanged(securityId: string, lots: CostBasisLot[]) {
    setLotOverrides((prev) => new Map(prev).set(securityId, lots));
    invalidate(qc, keys.costBasis, queries.investmentLots(securityId).queryKey, keys.portfolio);
  }

  const TOTAL_COLS = 8;

  return (
    <div className="flex flex-col">
      <PageHeader title="Cost Basis" />

      <StatRibbon borderTop={false} stats={[
        { label: "Total Positions",     value: String(summary.total_positions) },
        { label: "Complete",            value: String(summary.complete), highlight: summary.complete > 0 ? "positive" : undefined },
        { label: "Partial / Unknown",   value: String(summary.partial + summary.unknown), highlight: (summary.partial + summary.unknown) > 0 ? "negative" : undefined },
        { label: "Known Cost Basis",    value: formatCurrency(summary.known_cost_basis, true) },
      ]} />

      <div className="space-y-4 p-6">
        <Tabs<Filter> value={filter} onChange={setFilter} options={filterTabs} />

        <Card>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full min-w-[700px] text-sm">
                <thead>
                  <tr className="border-b text-xs text-muted-foreground">
                    <th className="w-6 pl-3 pr-0 py-2.5" />
                    <th className="px-4 py-2.5 text-left font-medium">Security</th>
                    <th className="px-4 py-2.5 text-right font-medium">Quantity</th>
                    <th className="px-4 py-2.5 text-right font-medium">Market Value</th>
                    <th className="px-4 py-2.5 text-right font-medium">Cost Basis</th>
                    <th className="px-4 py-2.5 text-right font-medium">Unrealized G/L</th>
                    <th className="px-4 py-2.5 text-right font-medium">Coverage</th>
                    <th className="px-4 py-2.5 text-right font-medium">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {filtered.map((p) => {
                    const gl = p.unrealized_gl;
                    const expanded = expandedIds.has(p.security_id);
                    const lots = lotOverrides.get(p.security_id) ?? p.lots;

                    return (
                      <Fragment key={p.security_id}>
                        <tr
                          onClick={() => toggleExpand(p.security_id)}
                          className="cursor-pointer transition-colors hover:bg-muted/40"
                        >
                          <td className="w-6 pl-3 pr-0 py-2.5">
                            <ChevronRight
                              size={14}
                              className={cn("text-muted-foreground transition-transform", expanded && "rotate-90")}
                            />
                          </td>
                          <td className="px-4 py-2.5">
                            <div
                              className={cn("w-fit", p.ticker && "cursor-pointer hover:underline")}
                              onClick={(e) => { if (p.ticker) { e.stopPropagation(); navigate(`/market/${p.ticker}`); } }}
                            >
                              <p className="max-w-40 truncate font-medium">{holdingDisplayName(p) ?? "—"}</p>
                              <p className="text-xs text-muted-foreground truncate max-w-40">{holdingSubtitle(p)}</p>
                            </div>
                          </td>
                          <td className="px-4 py-2.5 text-right tabular-nums">{p.current_quantity.toLocaleString()}</td>
                          <td className="px-4 py-2.5 text-right tabular-nums font-medium">{formatCurrency(p.current_value)}</td>
                          <td className="px-4 py-2.5 text-right tabular-nums text-muted-foreground">
                            {p.computed_cost_basis !== null ? formatCurrency(p.computed_cost_basis) : "—"}
                          </td>
                          <td className={cn(
                            "px-4 py-2.5 text-right tabular-nums",
                            gl === null ? "text-muted-foreground" : moneyColor(gl)
                          )}>
                            {gl !== null ? formatCurrency(gl) : "—"}
                          </td>
                          <td className="px-4 py-2.5 text-right"><CoverageCell position={p} /></td>
                          <td className="px-4 py-2.5 text-right"><StatusBadge status={p.status} /></td>
                        </tr>
                        {expanded && (
                          <tr>
                            <td colSpan={TOTAL_COLS} className="p-0">
                              <InvestmentLotsEditor
                                securityId={p.security_id}
                                lots={lots}
                                accounts={accounts}
                                onChanged={(next) => handleLotsChanged(p.security_id, next)}
                              />
                            </td>
                          </tr>
                        )}
                      </Fragment>
                    );
                  })}
                  {filtered.length === 0 && (
                    <tr>
                      <td colSpan={TOTAL_COLS} className="px-4 py-8 text-center text-muted-foreground">
                        {filter === "complete" && "No positions with complete cost basis data"}
                        {filter === "gaps" && "No positions with coverage gaps — great!"}
                        {filter === "all" && "No positions found"}
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
