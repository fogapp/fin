import { api } from "@/api/client";
import { categoryDisplayName } from "@/lib/categories";
import { EntityCombobox } from "@/components/EntityCombobox";
import type { Category, CategorySummary } from "@/api/types";
import { keys } from "@/api/keys";

interface Props {
  value: string;
  onChange: (categoryId: string) => void;
  categories: CategorySummary[];
  placeholder?: string;
  className?: string;
  inputClassName?: string;
  autoFocus?: boolean;
  onClose?: () => void;
}

/**
 * Category picker with a pinned "No category" clear row; the interaction model
 * lives in EntityCombobox. Options display as "Parent › Child", but creation
 * matching compares bare names so an existing child never re-creates.
 */
export function CategoryCombobox({ value, onChange, categories, placeholder = "Select category…", className, inputClassName, autoFocus, onClose }: Props) {
  const displayName = (c: CategorySummary) => categoryDisplayName(c, categories);

  return (
    <EntityCombobox
      value={value}
      onChange={onChange}
      items={categories}
      getId={(c) => c.id}
      getLabel={displayName}
      getMatchName={(c) => c.name}
      filter={(c, query) => displayName(c).toLowerCase().includes(query)}
      renderOption={displayName}
      ariaLabel="Category"
      placeholder={placeholder}
      className={className}
      inputClassName={inputClassName}
      autoFocus={autoFocus}
      onClose={onClose}
      create={{
        mutationFn: (name) => api.post<Category>("/categories", { name }),
        invalidateKey: keys.categories,
        label: (name) => <>Create &ldquo;{name}&rdquo;</>,
      }}
      sentinelLabel="No category"
      emptyMessage="No categories found"
    />
  );
}
