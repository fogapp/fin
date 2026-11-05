/**
 * Money-flow sankey. Node fill is assigned by node kind: income sources take
 * palette slot 2, the hub slot 1, savings slot 4, a savings shortfall the
 * negative color, and category nodes take the
 * palette slots in fixed order of appearance (9th+ falls back to neutral —
 * slots are never cycled). Node labels (name + value) render in normal ink;
 * links get a hover tooltip with the flow value; nodes are clickable.
 */
import { useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { Sankey, Tooltip, ResponsiveContainer, Rectangle } from "recharts";
import { formatCurrency } from "@/lib/utils";
import { seriesColor, useChartTheme, type ChartTheme } from "./theme";
import { TooltipRow, TooltipShell } from "./ChartTooltip";

export type SankeyNodeKind = "income_source" | "shortfall" | "hub" | "category" | "savings";

export interface SankeyNodeInput {
  name: string;
  kind: SankeyNodeKind;
  merchant_id?: string | null;
  category_id?: string | null;
  /** Group-dimension spend nodes: the parent category plus its children. */
  category_ids?: string[];
  /** Folded "Other" nodes: the rows folded into them, largest first. */
  members?: SankeyMember[];
}

export interface SankeyMember {
  name: string;
  value: number;
  merchant_id?: string | null;
  category_id?: string | null;
  category_ids?: string[];
}

export interface SankeyLinkInput {
  source: number;
  target: number;
  value: number;
}

export interface SankeyNodeDatum extends SankeyNodeInput {
  value: number;
}

interface SankeyChartProps {
  nodes: SankeyNodeInput[];
  links: SankeyLinkInput[];
  height?: number;
  valueFormat?: (v: number) => string;
  onSelect?: (datum: SankeyNodeDatum) => void;
  linkFor?: (datum: SankeyNodeDatum) => string | null;
}

function nodeColors(nodes: SankeyNodeInput[], theme: ChartTheme): string[] {
  let categoryIndex = 0;
  return nodes.map((n) => {
    switch (n.kind) {
      case "hub": return theme.series[0];
      case "income_source": return theme.series[1];
      case "shortfall": return theme.negative;
      case "savings": return theme.series[3];
      case "category": return seriesColor(theme, categoryIndex++);
    }
  });
}

interface NodeRenderProps {
  x: number;
  y: number;
  width: number;
  height: number;
  index: number;
  payload: { name: string; value: number; targetNodes: number[] };
}

interface TooltipEntry {
  name?: string | number;
  value?: number | string;
  payload?: {
    name?: string;
    value?: number;
    source?: { name?: string; kind?: SankeyNodeKind };
    target?: { name?: string; kind?: SankeyNodeKind };
  };
}

function SankeyTooltip({ active, payload, valueFormat }: {
  active?: boolean;
  payload?: ReadonlyArray<TooltipEntry>;
  valueFormat: (v: number) => string;
}) {
  if (!active || !payload?.length) return null;
  const entry = payload[0];
  const item = entry.payload ?? {};
  const value = typeof item.value === "number" ? item.value
    : typeof entry.value === "number" ? entry.value : null;
  if (value == null) return null;
  // Every link touches the hub, so a link is named by its other end —
  // "Mortgage", not "Income → Mortgage" (which reads as a subtraction).
  const name = item.source && item.target
    ? (item.source.kind === "hub" ? item.target.name : item.source.name) ?? ""
    : item.name ?? String(entry.name ?? "");
  return (
    <TooltipShell>
      <TooltipRow name={name} value={valueFormat(value)} />
    </TooltipShell>
  );
}

export function SankeyChart({
  nodes, links, height = 320, valueFormat = (v) => formatCurrency(v, true), onSelect, linkFor,
}: SankeyChartProps) {
  const theme = useChartTheme();
  const navigate = useNavigate();
  const colors = useMemo(() => nodeColors(nodes, theme), [nodes, theme]);
  const data = useMemo(
    () => ({ nodes: nodes.map((n) => ({ ...n })), links: links.map((l) => ({ ...l })) }),
    [nodes, links],
  );

  const interactive = Boolean(onSelect || linkFor);

  function activate(index: number, value: number) {
    const source = nodes[index];
    if (!source) return;
    const datum: SankeyNodeDatum = { ...source, value };
    onSelect?.(datum);
    const href = linkFor?.(datum);
    if (href) navigate(href);
  }

  // Long node names (bank memo lines) collide with the next column; cap
  // them and let the hover tooltip carry the full name.
  const MAX_LABEL = 34;
  function truncate(name: string) {
    return name.length > MAX_LABEL ? `${name.slice(0, MAX_LABEL - 1).trimEnd()}…` : name;
  }

  function renderNode(props: NodeRenderProps) {
    const { x, y, width, height: h, index, payload } = props;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return <g />;
    // Terminal nodes label to the left so text stays inside the plot.
    const terminal = payload.targetNodes.length === 0;
    const textX = terminal ? x - 6 : x + width + 6;
    const anchor = terminal ? "end" : "start";
    return (
      <g
        onClick={interactive ? () => activate(index, payload.value) : undefined}
        style={interactive ? { cursor: "pointer" } : undefined}
      >
        <Rectangle x={x} y={y} width={width} height={h} fill={colors[index]} fillOpacity={0.9} radius={2} />
        <text x={textX} y={y + h / 2 - 2} textAnchor={anchor} fontSize={11} fontWeight={500} fill="var(--color-foreground)">
          {truncate(payload.name)}
          {payload.name.length > MAX_LABEL && <title>{payload.name}</title>}
        </text>
        <text x={textX} y={y + h / 2 + 11} textAnchor={anchor} fontSize={10} fill={theme.muted}>
          {valueFormat(payload.value)}
        </text>
      </g>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={height}>
      <Sankey
        data={data}
        node={renderNode}
        link={{ stroke: theme.mode === "dark" ? "#4a4a47" : "#c3c2b7", strokeOpacity: 0.4, fill: "none" }}
        nodePadding={24}
        nodeWidth={10}
        margin={{ top: 8, right: 120, bottom: 8, left: 120 }}
      >
        <Tooltip
          isAnimationActive={false}
          content={<SankeyTooltip valueFormat={valueFormat} />}
        />
      </Sankey>
    </ResponsiveContainer>
  );
}
