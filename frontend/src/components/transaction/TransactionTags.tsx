import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { X, Plus } from "lucide-react";
import { queries } from "@/api/queries";
import { Input } from "@/components/ui/input";
import { useTransactionMutations } from "@/hooks/mutations/useTransactionMutations";
import type { CashTransaction } from "@/api/types";

/** A transaction's tag pills with an inline search-or-create picker — shared
 *  by the transaction drawer and the detail page. */
export function TransactionTags({ tx, label = "Tags" }: { tx: CashTransaction; label?: string | null }) {
  const [addingTag, setAddingTag] = useState(false);
  const [tagSearch, setTagSearch] = useState("");
  const { data: allTags = [] } = useQuery({ ...queries.tags(), enabled: addingTag });
  const { addTag, removeTag, createAndAddTag } = useTransactionMutations(tx.id);

  // Close the picker when the host switches to another transaction
  // (adjust-state-during-render instead of an effect).
  const [prevTxId, setPrevTxId] = useState(tx.id);
  if (prevTxId !== tx.id) {
    setPrevTxId(tx.id);
    setAddingTag(false);
    setTagSearch("");
  }

  const existingTagIds = new Set(tx.tags.map((t) => t.id));
  const filteredTags = allTags.filter(
    (t) => !existingTagIds.has(t.id) && t.name.toLowerCase().includes(tagSearch.toLowerCase())
  );
  const canCreate = tagSearch.trim().length > 0 && !allTags.some(
    (t) => t.name.toLowerCase() === tagSearch.trim().toLowerCase()
  );

  function closeTagPicker() { setAddingTag(false); setTagSearch(""); }
  function pickTag(tagId: string) { addTag.mutate(tagId); closeTagPicker(); }
  function createTag() { if (tagSearch.trim()) { createAndAddTag.mutate(tagSearch.trim()); closeTagPicker(); } }

  return (
    <div className="space-y-2">
      {label && <p className="text-xs font-medium text-muted-foreground">{label}</p>}
      <div className="flex flex-wrap gap-1.5">
        {tx.tags.map((tag) => (
          <span
            key={tag.id}
            className="group flex items-center gap-1 rounded-full border border-primary/30 bg-primary/8 px-2.5 py-0.5 text-xs text-primary"
          >
            {tag.name}
            <button
              onClick={() => removeTag.mutate(tag.id)}
              className="rounded-full opacity-50 hover:opacity-100 transition-opacity focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              aria-label={`Remove tag ${tag.name}`}
            >
              <X size={10} />
            </button>
          </span>
        ))}

        {addingTag ? (
          <div className="w-full space-y-2">
            <form onSubmit={(e) => { e.preventDefault(); if (canCreate) createTag(); else if (filteredTags[0]) pickTag(filteredTags[0].id); }}>
              <Input
                autoFocus
                value={tagSearch}
                onChange={(e) => setTagSearch(e.target.value)}
                placeholder="Search or create tag…"
                aria-label="Search or create tag"
                className="h-7 px-2.5 text-xs"
              />
            </form>
            <div className="flex flex-wrap gap-1.5">
              {filteredTags.map((tag) => (
                <button
                  key={tag.id}
                  onClick={() => pickTag(tag.id)}
                  className="rounded-full border border-border px-2.5 py-0.5 text-xs text-muted-foreground hover:border-primary/30 hover:bg-primary/8 hover:text-primary transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  {tag.name}
                </button>
              ))}
              {canCreate && (
                <button
                  onClick={createTag}
                  className="rounded-full border border-dashed border-primary/40 px-2.5 py-0.5 text-xs text-primary hover:bg-primary/8 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  Create "{tagSearch.trim()}"
                </button>
              )}
              {filteredTags.length === 0 && !canCreate && (
                <span className="text-xs text-muted-foreground">No tags available</span>
              )}
            </div>
            <button onClick={closeTagPicker} className="rounded text-xs text-muted-foreground hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
              Cancel
            </button>
          </div>
        ) : (
          <button
            onClick={() => setAddingTag(true)}
            className="flex items-center gap-0.5 rounded-full border border-dashed border-border px-2.5 py-0.5 text-xs text-muted-foreground hover:border-primary/30 hover:text-primary transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <Plus size={10} />
            Add tag
          </button>
        )}
      </div>
    </div>
  );
}
