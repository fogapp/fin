import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Tags, ChevronRight, Plus, Pencil, Trash2, Settings2 } from "lucide-react";
import { MasterDetailShell, MasterDetailLoading } from "@/components/MasterDetailShell";
import { InlineCreateForm } from "@/components/InlineCreateForm";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogHeader, DialogFooter } from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { useConfirm } from "@/components/ui/confirm";
import { ErrorState } from "@/components/PageState";
import { PageHeader } from "@/components/layout/PageHeader";
import { SpendByMonthTable } from "@/components/SpendByMonthTable";
import { StatRibbon } from "@/components/StatRibbon";
import { ResponsiveTransactionView as TransactionTable } from "@/components/TransactionList";
import { ChartLabel, useChartTheme } from "@/components/charts";
import { usePageTimeframe } from "@/hooks/useTimeframeButtons";
import { SpendChartCard, useSpendChartControls } from "@/components/spend-chart";
import { formatCurrency, fillLastMonths } from "@/lib/utils";
import { mtdVsProratedPrior } from "@/lib/statFormat";
import type { Category, CategorySummary } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

export function Categories() {
  const { data: categories = [], isLoading, isError, refetch } = useQuery(queries.categories());

  // Build tree: top-level categories with subcategories nested
  const topLevel = categories.filter((c) => c.parent_id === null);
  const byParent = categories.reduce<Record<string, CategorySummary[]>>((acc, c) => {
    if (c.parent_id != null) {
      (acc[c.parent_id] ??= []).push(c);
    }
    return acc;
  }, {});

  return (
    <MasterDetailShell
      title="Categories"
      noun="category"
      nounPlural="categories"
      icon={Tags}
      items={categories}
      isLoading={isLoading}
      isError={isError}
      refetch={refetch}
      renderNewForm={({ onCreated, onCancel }) => (
        <NewCategoryForm
          topLevelCategories={topLevel}
          onCreated={onCreated}
          onCancel={onCancel}
        />
      )}
      // A flat searched list, but a two-level tree when browsing — so the page
      // supplies the whole list body instead of a row renderer.
      renderListBody={({ filtered: searchResults, highlightedIndex, isSearching, selectedId, toggleSelected, openNew }) =>
        isSearching ? (
          <>
            {searchResults.map((c, i) => (
              <CategoryRow
                key={c.id}
                category={c}
                selected={c.id === selectedId}
                highlighted={i === highlightedIndex}
                onClick={() => toggleSelected(c.id)}
              />
            ))}
            {searchResults.length === 0 && (
              <EmptyState title="No categories match the current filters." />
            )}
          </>
        ) : topLevel.length === 0 ? (
          <EmptyState
            icon={Tags}
            title="No categories yet."
            action={<Button size="sm" onClick={openNew}>New category</Button>}
          />
        ) : (
          topLevel.map((c) => (
            <div key={c.id}>
              <CategoryRow
                category={c}
                selected={c.id === selectedId}
                onClick={() => toggleSelected(c.id)}
              />
              {(byParent[c.id] ?? []).map((sub) => (
                <CategoryRow
                  key={sub.id}
                  category={sub}
                  selected={sub.id === selectedId}
                  onClick={() => toggleSelected(sub.id)}
                  indent
                />
              ))}
            </div>
          ))
        )
      }
      renderDetail={(id, setSelectedId) => (
        <CategoryDetail
          id={id}
          allCategories={categories}
          onNavigate={setSelectedId}
        />
      )}
    />
  );
}

// ── New category inline form ──────────────────────────────────────────────────

function NewCategoryForm({ topLevelCategories, onCreated, onCancel }: {
  topLevelCategories: CategorySummary[];
  onCreated: (id: string) => void;
  onCancel: () => void;
}) {
  const [parentId, setParentId] = useState("");
  return (
    <InlineCreateForm
      endpoint="/categories"
      invalidateKey={keys.categories}
      placeholder="Category name"
      extraBody={{ parent_id: parentId || null }}
      onCreated={onCreated}
      onCancel={onCancel}
    >
      <Select
        value={parentId}
        onChange={(e) => setParentId(e.target.value)}
        aria-label="Parent category"
        className="h-8 text-sm text-muted-foreground"
      >
        <option value="">No parent</option>
        {topLevelCategories.map((c) => (
          <option key={c.id} value={c.id}>{c.name}</option>
        ))}
      </Select>
    </InlineCreateForm>
  );
}

// ── CategoryRow ───────────────────────────────────────────────────────────────

function CategoryRow({ category, selected, highlighted = false, onClick, indent = false }: {
  category: CategorySummary;
  selected: boolean;
  highlighted?: boolean;
  onClick: () => void;
  indent?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex w-full items-center justify-between px-4 py-2.5 text-left text-sm transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary
        ${indent ? "pl-8" : ""}
        ${selected ? "bg-primary/8 text-primary" : ""}
        ${highlighted && !selected ? "bg-accent" : ""}`}
    >
      <div className="flex items-center gap-1.5 min-w-0">
        {indent && <ChevronRight size={12} className="shrink-0 text-muted-foreground" />}
        <span className="truncate">{category.name}</span>
      </div>
      {category.transaction_count > 0 && (
        <span className="ml-2 shrink-0 text-xs text-muted-foreground">
          {category.transaction_count.toLocaleString()}
        </span>
      )}
    </button>
  );
}

// ── CategoryDetail ────────────────────────────────────────────────────────────

function CategoryDetail({ id, allCategories, onNavigate }: {
  id: string;
  allCategories: CategorySummary[];
  onNavigate: (id: string | null) => void;
}) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const { data, isLoading, error, refetch } = useQuery(queries.category(id));
  // Include subcategory IDs so parent categories show all descendant transactions
  const allCategoryIds = [id, ...(data?.subcategories ?? []).map((s) => s.id)];
  const { data: transactions = [], isLoading: txLoading, isError: txError, refetch: refetchTx } = useQuery({
    ...queries.categoryTransactions(allCategoryIds),
    enabled: !isLoading,
  });

  const [adding, setAdding] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [draftName, setDraftName] = useState("");
  const [merchantFilter, setMerchantFilter] = useState<string | null>(null);
  const [monthFilter, setMonthFilter] = useState<string | null>(null);
  const setParent = useMutation({
    mutationFn: (parentId: string | null) =>
      api.patch(`/categories/${id}`, { parent_id: parentId }),
    onSuccess: () => {
      invalidate(qc, keys.categories);
    },
  });

  const rename = useMutation({
    mutationFn: (name: string) => api.patch(`/categories/${id}`, { name }),
    onSuccess: () => {
      invalidate(qc, keys.categories);
      setEditingName(false);
    },
  });

  const setCharitable = useMutation({
    mutationFn: (charitable: boolean) => api.patch(`/categories/${id}`, { charitable }),
    onSuccess: () => {
      invalidate(qc, keys.categories, keys.taxReport);
    },
  });

  const deleteCategory = useMutation({
    mutationFn: () => api.delete(`/categories/${id}`),
    onSuccess: () => {
      invalidate(qc, keys.categories);
      onNavigate(null);
    },
  });


  if (isLoading) return <MasterDetailLoading />;
  if (error || !data) return (
    <ErrorState title="Failed to load category" onRetry={() => refetch()} />
  );

  const spendData = fillLastMonths(data.monthly_spend);
  const rollupData = fillLastMonths(data.monthly_spend_rollup);

  const merchantData = Object.entries(data.by_merchant)
    .slice(0, 10)
    .map(([name, amount]) => ({ name, amount }));

  const hasSubcategories = data.subcategories.length > 0;

  // MTD spend vs prorated prior month (rollup if parent, own if subcategory)
  const chartData = hasSubcategories ? rollupData : spendData;
  const { mtd: mtdSpend, change: mtdChange } = mtdVsProratedPrior(chartData);

  // Top-level categories available as parents (excluding self and subcategories)
  const parentOptions = allCategories.filter(
    (c) => c.parent_id === null && c.id !== id
  );

  return (
    <div className="flex flex-col">
      {/* Header bar */}
      {editingName ? (
        <div className="flex h-14 items-center border-b px-6">
          <form
            className="flex w-full items-center gap-2"
            onSubmit={(e) => { e.preventDefault(); if (draftName.trim()) rename.mutate(draftName.trim()); }}
          >
            <Input
              autoFocus
              value={draftName}
              onChange={(e) => setDraftName(e.target.value)}
              onKeyDown={(e) => e.key === "Escape" && setEditingName(false)}
              aria-label="Category name"
              className="h-8 max-w-xs font-semibold"
            />
            <Button type="button" variant="ghost" size="xs" onClick={() => setEditingName(false)}>
              Cancel
            </Button>
            <Button type="submit" size="xs" disabled={rename.isPending || !draftName.trim()}>
              Save
            </Button>
          </form>
        </div>
      ) : (
        <PageHeader
          title={data.name}
          subtitle={data.parent?.name}
          back={data.parent ? { to: `/categories#id=${data.parent.id}`, label: `Back to ${data.parent.name}` } : undefined}
          actions={[
            { label: "Rename", icon: Pencil, onSelect: () => { setDraftName(data.name); setEditingName(true); } },
            { label: "Category settings", icon: Settings2, onSelect: () => setShowSettings(true) },
            {
              label: "Delete category",
              icon: Trash2,
              destructive: true,
              disabled: deleteCategory.isPending,
              onSelect: async () => {
                if (await confirm({
                  title: `Delete "${data.name}"?`,
                  description: "This cannot be undone.",
                  confirmLabel: "Delete",
                  destructive: true,
                })) {
                  deleteCategory.mutate();
                }
              },
            },
          ]}
        />
      )}

      {showSettings && (
        <Dialog open onOpenChange={(open) => { if (!open) setShowSettings(false); }}>
          <DialogContent size="sm">
            <DialogHeader title={`${data.name} settings`} />
            <div className="space-y-5 px-6 py-5">
              <div className="space-y-1.5">
                <Label htmlFor="category-parent">Parent category</Label>
                <Select
                  id="category-parent"
                  value={data.parent?.id ?? ""}
                  onChange={(e) => setParent.mutate(e.target.value || null)}
                >
                  <option value="">No parent</option>
                  {parentOptions.map((c) => (
                    <option key={c.id} value={c.id}>{c.name}</option>
                  ))}
                </Select>
              </div>
              <label className="flex cursor-pointer select-none items-start gap-2 text-sm">
                <Checkbox
                  checked={data.charitable ?? false}
                  onChange={(e) => setCharitable.mutate(e.target.checked)}
                  aria-label="Charitable category"
                  className="mt-0.5"
                />
                <span>
                  Charitable
                  <span className="block text-xs text-muted-foreground">
                    Transactions here count as charitable gifts in the tax center.
                  </span>
                </span>
              </label>
            </div>
            <DialogFooter>
              <Button size="sm" onClick={() => setShowSettings(false)}>Done</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      )}

      <StatRibbon borderTop={false} stats={[
        { label: "MTD Spend",    value: formatCurrency(mtdSpend),         change: mtdChange,      invertColor: true },
        { label: "Total Spend",  value: formatCurrency(data.total_spend), invertColor: true },
        { label: "Returns",      value: formatCurrency(data.total_returns) },
        { label: "Txns",         value: data.total_count.toLocaleString() },
      ]} />

      <div className="p-6 space-y-6">
        {/* Monthly spend chart — the shared segmented spend card, scoped to
            this category's rollup. A month click filters the in-page table
            below rather than navigating: a URL filter can't express "this
            category or its children". Keyed by id so the split default
            re-derives when navigating between categories. */}
        <CategorySpendChart
          key={id}
          categoryId={id}
          hasSubcategories={hasSubcategories}
          onSelectMonth={(month) => setMonthFilter((prev) => (prev === month ? null : month))}
        />

        {/* Two-column: transactions + right sidebar */}
        <div className="grid gap-6 lg:grid-cols-[1fr_240px]">
          {/* Transactions */}
          <div>
            <ChartLabel>Transactions</ChartLabel>
            <Card>
              <CardContent className="p-0">
                {txError ? (
                  <ErrorState title="Failed to load transactions" onRetry={() => refetchTx()} />
                ) : (
                  <TransactionTable
                    transactions={transactions}
                    isLoading={txLoading}
                    columns={["date", "description", "merchant", "amount"]}
                    resetKey={`${id}-${monthFilter}-${merchantFilter}`}
                    exportScope={{ category_id: id }}
                    initialFilters={[
                      ...(monthFilter ? [{ _key: 1, field: "transaction_date", operator: "month", value: monthFilter }] : []),
                      ...(merchantFilter
                        ? [merchantFilter === "Unknown"
                            ? { _key: 2, field: "merchant_name", operator: "blank", value: "" }
                            : { _key: 2, field: "merchant_name", operator: "equals", value: merchantFilter }]
                        : []),
                    ]}
                  />
                )}
              </CardContent>
            </Card>
          </div>

          {/* Right sidebar */}
          <div className="space-y-6">
            {/* Subcategories */}
            <div>
              {data.subcategories.length > 0 && (
                <>
                  <ChartLabel>Subcategories</ChartLabel>
                  <div className="space-y-px rounded-xl overflow-hidden border">
                    {data.subcategories.map((sub) => (
                      <button
                        key={sub.id}
                        onClick={() => onNavigate(sub.id)}
                        className="flex w-full items-center justify-between px-4 py-2.5 text-sm bg-card hover:bg-accent transition-colors text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
                      >
                        <span>{sub.name}</span>
                        <div className="flex items-center gap-4 text-xs text-muted-foreground">
                          <span>{sub.transaction_count.toLocaleString()} txns</span>
                          <span>{formatCurrency(sub.total_spend)}</span>
                          <ChevronRight size={14} />
                        </div>
                      </button>
                    ))}
                  </div>
                </>
              )}
              {!data.parent_id && (
                adding ? (
                  <AddSubcategoryForm parentId={id} onDone={() => setAdding(false)} />
                ) : (
                  <Button
                    variant="ghost"
                    size="xs"
                    onClick={() => setAdding(true)}
                    className="mt-1 -ml-2.5 gap-1 text-muted-foreground hover:text-foreground"
                  >
                    <Plus size={11} />
                    Add subcategory
                  </Button>
                )
              )}
            </div>

            {/* Top merchants */}
            {merchantData.length > 0 && (
              <div>
                <ChartLabel>Top Merchants</ChartLabel>
                <MerchantSpendList
                  data={merchantData}
                  onSelect={(name) => setMerchantFilter((prev) => prev === name ? null : name)}
                />
              </div>
            )}

            {/* Spend by month table */}
            <SpendByMonthTable data={chartData} />

          </div>
        </div>
      </div>
    </div>
  );
}

// ── CategorySpendChart ────────────────────────────────────────────────────────

/** The shared spend chart wired for a category page: its own timeframe and
 *  mode controls (no page-level header scopes anything beyond the chart),
 *  defaulting to the by-category split — i.e. subcategories — when there is
 *  one. Callers key this by category id so the default re-derives on
 *  navigation. */
function CategorySpendChart({ categoryId, hasSubcategories, onSelectMonth }: {
  categoryId: string;
  hasSubcategories: boolean;
  onSelectMonth: (month: string) => void;
}) {
  const timeframe = usePageTimeframe("categories", "category-spend-timeframe");
  const controls = useSpendChartControls({ defaultDimension: hasSubcategories ? "category" : "none" });
  return (
    <SpendChartCard
      scope={{ categoryId }}
      timeframe={timeframe}
      controls={controls}
      showSeriesToggle
      showTimeframeSelector
      onSelectMonth={onSelectMonth}
    />
  );
}

// ── AddSubcategoryForm ────────────────────────────────────────────────────────

function AddSubcategoryForm({ parentId, onDone }: { parentId: string; onDone: () => void }) {
  const qc = useQueryClient();
  const [name, setName] = useState("");
  const create = useMutation({
    mutationFn: () => api.post<Category>("/categories", { name: name.trim(), parent_id: parentId }),
    onSuccess: () => {
      invalidate(qc, keys.categories);
      onDone();
    },
  });

  return (
    <form
      onSubmit={(e) => { e.preventDefault(); if (name.trim()) create.mutate(); }}
      className="mt-2 flex items-center gap-1.5"
    >
      <Input
        autoFocus
        value={name}
        onChange={(e) => setName(e.target.value)}
        onKeyDown={(e) => e.key === "Escape" && onDone()}
        placeholder="Subcategory name"
        aria-label="Subcategory name"
        className="h-8 flex-1 px-2.5"
      />
      <Button type="button" variant="outline" size="xs" onClick={onDone}>
        Cancel
      </Button>
      <Button type="submit" size="xs" disabled={create.isPending || !name.trim()}>
        Add
      </Button>
    </form>
  );
}

// ── MerchantSpendList ─────────────────────────────────────────────────────────

function MerchantSpendList({ data, onSelect }: {
  data: { name: string; amount: number }[];
  onSelect?: (name: string) => void;
}) {
  const theme = useChartTheme();
  const max = Math.max(...data.map((d) => d.amount));
  return (
    <div className="space-y-1.5">
      {data.map(({ name, amount }) => (
        <button
          key={name}
          onClick={() => onSelect?.(name)}
          className="w-full text-left rounded-md px-1.5 py-1 -mx-1.5 transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          <div className="flex items-baseline justify-between gap-2 text-xs mb-0.5">
            <span className="truncate text-foreground">{name}</span>
            <span className="shrink-0 tabular-nums text-muted-foreground">{formatCurrency(amount)}</span>
          </div>
          <div className="h-1 w-full rounded-full bg-muted overflow-hidden">
            <div
              className="h-full rounded-full"
              style={{ width: `${(amount / max) * 100}%`, background: theme.series[0] }}
            />
          </div>
        </button>
      ))}
    </div>
  );
}
