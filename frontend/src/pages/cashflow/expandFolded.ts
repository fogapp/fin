import type { SankeyLinkInput, SankeyNodeInput } from "@/components/charts";

/** How many folded rows each side's "Other" node has been expanded into. */
export type FoldReveal = { income_source: number; category: number };

/** Pulls the first `reveal[kind]` members out of each folded "Other" node
 *  as nodes of their own; whatever is left stays folded under the original
 *  name. A folded node has a single link (to or from the hub), which is
 *  split across the pieces so the hub stays balanced. */
export function expandFolded(
  nodes: SankeyNodeInput[],
  links: SankeyLinkInput[],
  reveal: FoldReveal,
): { nodes: SankeyNodeInput[]; links: SankeyLinkInput[] } {
  const out: SankeyNodeInput[] = [];
  // Old node index → the new nodes it became, each with the value it carries
  // (null = unchanged, keep the link's own value).
  const pieces: { index: number; value: number | null }[][] = [];

  nodes.forEach((node, i) => {
    const count = node.members?.length && (node.kind === "income_source" || node.kind === "category")
      ? Math.min(reveal[node.kind], node.members.length)
      : 0;
    if (!node.members || count === 0) {
      pieces[i] = [{ index: out.length, value: null }];
      out.push(node);
      return;
    }
    const shown = node.members.slice(0, count);
    const rest = node.members.slice(count);
    pieces[i] = [];
    for (const { value, ...member } of shown) {
      pieces[i].push({ index: out.length, value });
      out.push({ ...member, kind: node.kind });
    }
    if (rest.length) {
      const value = Math.round(rest.reduce((sum, m) => sum + m.value, 0) * 100) / 100;
      pieces[i].push({ index: out.length, value });
      out.push({ name: node.name, kind: node.kind, members: rest });
    }
  });

  const outLinks = links.flatMap((link) => {
    const sources = pieces[link.source];
    const targets = pieces[link.target];
    if (sources.length === 1 && targets.length === 1) {
      return [{ source: sources[0].index, target: targets[0].index, value: link.value }];
    }
    return sources.length > 1
      ? sources.map((p) => ({ source: p.index, target: targets[0].index, value: p.value ?? link.value }))
      : targets.map((p) => ({ source: sources[0].index, target: p.index, value: p.value ?? link.value }));
  }).filter((link) => link.value > 0);

  return { nodes: out, links: outLinks };
}
