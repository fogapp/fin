import { useState, useEffect, useRef } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { cn } from "@/lib/utils";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/toast";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";

// ── Bulk action bar ───────────────────────────────────────────────────────────

export function BulkActionBar({ selectedIds, onClear }: {
  selectedIds: Set<string>;
  onClear: () => void;
}) {
  const qc = useQueryClient();
  const [action, setAction] = useState<"merchant" | "category" | "tags" | null>(null);
  const [search, setSearch] = useState("");
  const barRef = useRef<HTMLDivElement>(null);
  const [dropdownPos, setDropdownPos] = useState<{ left: number; top: number } | null>(null);

  useEffect(() => {
    if (action && barRef.current) {
      const r = barRef.current.getBoundingClientRect();
      setDropdownPos({ left: r.left, top: r.bottom + 4 });
    } else {
      setDropdownPos(null);
    }
  }, [action]);

  const { data: merchants = [] } = useQuery({ ...queries.merchants(), enabled: action === "merchant" });
  const { data: categories = [] } = useQuery({ ...queries.categories(), enabled: action === "category" });
  const { data: allTags = [] } = useQuery({ ...queries.tags(), enabled: action === "tags" });

  function closeAction() { setAction(null); setSearch(""); }
  function toggleAction(a: typeof action) { setAction((p) => { setSearch(""); return p === a ? null : a; }); }

  const ids = [...selectedIds];

  // One bulk_update request for the whole selection instead of a request per
  // row — 250 rows used to mean 250 PATCHes, each with its own cache bump and
  // follow-up jobs. Bulk apply is the legitimate full-invalidation case: many
  // rows changed, so one refetch at the end is cheaper than patching each row
  // into the cache.
  function done() {
    invalidate(qc, keys.cashTransactions, keys.tags);
    closeAction();
    onClear();
  }

  function failedAll() {
    // The bulk endpoint is all-or-nothing; keep the selection so the action
    // can be retried.
    toast.error(`Failed to update ${ids.length} rows`);
    closeAction();
  }

  const bulkUpdate = useMutation({
    mutationFn: (payload: { merchant_id?: string; category_id?: string; tag_ids?: string[] }) =>
      api.post("/cash_transactions/bulk_update", { ids, ...payload }),
    onSuccess: done,
    onError: failedAll,
  });
  const bulkMerchant = { mutate: (merchantId: string) => bulkUpdate.mutate({ merchant_id: merchantId }), isPending: bulkUpdate.isPending };
  const bulkCategory = { mutate: (categoryId: string) => bulkUpdate.mutate({ category_id: categoryId }), isPending: bulkUpdate.isPending };
  const bulkAddTag = { mutate: (tagId: string) => bulkUpdate.mutate({ tag_ids: [tagId] }), isPending: bulkUpdate.isPending };

  const isPending = bulkMerchant.isPending || bulkCategory.isPending || bulkAddTag.isPending;

  const filteredMerchants = merchants.filter((m) => m.name.toLowerCase().includes(search.toLowerCase()));
  const filteredCategories = categories.filter((c) => c.name.toLowerCase().includes(search.toLowerCase()));
  const filteredTags = allTags.filter((t) => t.name.toLowerCase().includes(search.toLowerCase()));

  return (
    <div ref={barRef} className="flex items-center gap-3 border-b px-3 py-1.5 text-xs">
      <span className="font-medium text-foreground">{ids.length} selected</span>
      <div className="h-3 w-px bg-border" />
      {(["merchant", "category", "tags"] as const).map((a) => (
        <button
          key={a}
          onClick={() => toggleAction(a)}
          className={cn(
            "rounded px-2 py-0.5 transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
            action === a ? "bg-accent text-foreground" : "text-muted-foreground"
          )}
        >
          {a === "merchant" ? "Assign merchant" : a === "category" ? "Assign category" : "Assign tags"}
        </button>
      ))}
      <div className="h-3 w-px bg-border" />
      <button onClick={onClear} className="rounded text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
        Clear
      </button>

      {action && dropdownPos && (
        <>
          <div className="fixed inset-0 z-[25]" onClick={closeAction} />
          <div className="fixed z-[30] w-56 overflow-hidden rounded-lg border bg-card shadow-lg"
            style={{ left: dropdownPos.left, top: dropdownPos.top }}>
            <div className="p-2">
              <Input
                autoFocus
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder={`Search ${action}s…`}
                aria-label={`Search ${action}s`}
                className="h-7 px-2.5 text-xs"
              />
            </div>
            <div className="max-h-52 overflow-y-auto">
              {isPending && (
                <p className="px-3 py-2 text-center text-xs text-muted-foreground">Updating…</p>
              )}
              {!isPending && action === "merchant" && filteredMerchants.map((m) => (
                <button key={m.id} onClick={() => bulkMerchant.mutate(m.id)}
                  className="flex w-full items-center px-3 py-2 text-left text-xs hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary">
                  {m.name}
                </button>
              ))}
              {!isPending && action === "category" && filteredCategories.map((c) => (
                <button key={c.id} onClick={() => bulkCategory.mutate(c.id)}
                  className="flex w-full items-center px-3 py-2 text-left text-xs hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary">
                  {c.name}
                </button>
              ))}
              {!isPending && action === "tags" && filteredTags.map((t) => (
                <button key={t.id} onClick={() => bulkAddTag.mutate(t.id)}
                  className="flex w-full items-center px-3 py-2 text-left text-xs hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary">
                  {t.name}
                </button>
              ))}
              {!isPending && (
                (action === "merchant" && filteredMerchants.length === 0) ||
                (action === "category" && filteredCategories.length === 0) ||
                (action === "tags" && filteredTags.length === 0)
              ) && (
                <p className="px-3 py-2 text-center text-xs text-muted-foreground">No results</p>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
