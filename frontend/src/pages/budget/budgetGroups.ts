import type { BudgetLine } from "@/api/types";

/** A top-level category and the budget lines under it. */
export interface BudgetGroup {
  /** The top-level category id. */
  id: string;
  name: string;
  /** The top-level category's own line, when it is budgeted itself. */
  line: BudgetLine | null;
  /** Subcategories budgeted on their own, largest first. */
  children: BudgetLine[];
  /** Planned across the group — the sort key. */
  planned: number;
}

/**
 * Nest subcategory lines under their parent so a parent's total visibly sits
 * above the subcategories carved out of it. A subcategory whose parent isn't
 * budgeted still groups under the parent's name. Largest groups first.
 */
export function groupLines(lines: BudgetLine[]): BudgetGroup[] {
  const groups = new Map<string, BudgetGroup>();
  for (const line of lines) {
    const id = line.parent_id ?? line.category_id;
    let group = groups.get(id);
    if (!group) {
      group = { id, name: line.parent_name ?? line.category_name, line: null, children: [], planned: 0 };
      groups.set(id, group);
    }
    if (line.parent_id) group.children.push(line);
    else {
      group.line = line;
      group.name = line.category_name;
    }
    group.planned += line.planned;
  }
  return [...groups.values()]
    .map((g) => ({ ...g, children: [...g.children].sort((a, b) => b.planned - a.planned) }))
    .sort((a, b) => b.planned - a.planned);
}

/** Lines in display order: each group's own line, then its subcategories. */
export function orderedLines(lines: BudgetLine[]): BudgetLine[] {
  return groupLines(lines).flatMap((g) => [...(g.line ? [g.line] : []), ...g.children]);
}

/** What a line has to spend this period: its amount plus any rollover. */
export function available(line: Pick<BudgetLine, "planned" | "rollover_amount">): number {
  return line.planned + line.rollover_amount;
}
