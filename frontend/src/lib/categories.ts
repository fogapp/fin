import type { CategorySummary } from "@/api/types";

/** "Child" for a root category, "Parent › Child" for a subcategory. */
export function categoryDisplayName(category: CategorySummary, categories: CategorySummary[]): string {
  if (!category.parent_id) return category.name;
  const parent = categories.find((p) => p.id === category.parent_id);
  return parent ? `${parent.name} › ${category.name}` : category.name;
}
