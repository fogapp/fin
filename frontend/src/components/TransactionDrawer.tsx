import { useState } from "react";
import { useDrawerKeyboard } from "@/hooks/useDrawerKeyboard";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { X, ArrowUpRight, Pencil, Search, Zap } from "lucide-react";
import { formatCurrency, formatDate, cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { queries } from "@/api/queries";
import { MerchantCombobox } from "@/components/MerchantCombobox";
import { CategoryCombobox } from "@/components/CategoryCombobox";
import { QuickAutomationModal } from "@/components/QuickAutomationModal";
import { TransactionTags } from "@/components/transaction/TransactionTags";
import { TransferTools } from "@/components/transaction/TransferTools";
import { useTransferState } from "@/components/transaction/useTransferState";
import { amountColor, transferKindLabel } from "@/lib/transactions";
import { searchEngineById, searchUrl } from "@/lib/searchEngines";
import { useTransactionDefaults } from "@/hooks/useTransactionDefaults";
import { useTransactionMutations } from "@/hooks/mutations/useTransactionMutations";
import type { CashTransaction, SimilarTransaction } from "@/api/types";

// ── Drawer ────────────────────────────────────────────────────────────────────

export function TransactionDrawer({ tx, headerHeight, onClose, onPrev, onNext, onFirst, onLast }: {
  tx: CashTransaction;
  headerHeight?: number;
  onClose: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  onFirst?: () => void;
  onLast?: () => void;
}) {
  const navigate = useNavigate();
  const { searchEngine } = useTransactionDefaults();
  const { counterpartyName } = useTransferState(tx);
  const { patch: patchTx } = useTransactionMutations(tx.id);

  const [memoValue, setMemoValue] = useState(tx.memo ?? "");
  const [editingMerchant, setEditingMerchant] = useState(false);
  const [editingCategory, setEditingCategory] = useState(false);
  const [automating, setAutomating] = useState(false);
  // Reset per-transaction edit state when the drawer switches to another tx
  // (adjust-state-during-render pattern instead of setState in an effect).
  const [prevTxId, setPrevTxId] = useState(tx.id);
  if (prevTxId !== tx.id) {
    setPrevTxId(tx.id);
    setMemoValue(tx.memo ?? "");
    setEditingMerchant(false);
    setEditingCategory(false);
    setAutomating(false);
  }
  const { data: merchants = [] } = useQuery(queries.merchants());
  const { data: categories = [] } = useQuery(queries.categories());

  useDrawerKeyboard({ onClose, onPrev, onNext, onFirst, onLast });

  return (
    <>
      <div className="flex h-full w-80 flex-col bg-card">
        <div data-sidebar className="flex items-center justify-between border-b bg-card px-3 text-card-foreground" style={headerHeight ? { height: headerHeight } : undefined}>
          <div className="flex items-center gap-1.5">
            <p className="text-xs font-medium">Transaction</p>
            <button
              onClick={() => { onClose(); navigate(`/transactions/${tx.id}`); }}
              className="rounded p-0.5 text-muted-foreground hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              title="Open full detail page"
              aria-label="Open full detail page"
            >
              <ArrowUpRight size={14} />
            </button>
          </div>
          <div className="flex items-center gap-1">
            <button
              onClick={onClose}
              className="rounded p-0.5 hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              aria-label="Close"
            >
              <X size={15} />
            </button>
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {/* Amount */}
          <div className="rounded-xl border p-4 text-center">
            <p className={cn("text-2xl font-semibold tabular-nums", amountColor(tx))}>
              {formatCurrency(tx.amount)}
            </p>
            {/* Fin's view first: a linked row is a card payment / loan
                payment / transfer whatever the bank called it. The imported
                type stays visible underneath so the raw feed is never hidden. */}
            {tx.transfer_id ? (
              <>
                <p className="mt-0.5 text-xs font-medium">
                  {transferKindLabel(tx.transfer_kind)}
                  {counterpartyName && ` · ${tx.amount > 0 ? "from" : "to"} ${counterpartyName}`}
                </p>
                <p className="text-caption text-muted-foreground capitalize">
                  imported as {tx.transaction_type?.toLowerCase() ?? "—"} · {tx.source.replace("_", " ")}
                </p>
              </>
            ) : (
              <p className="mt-0.5 text-xs text-muted-foreground capitalize">
                {tx.transaction_type?.toLowerCase() ?? "—"} · {tx.source.replace("_", " ")}
              </p>
            )}
          </div>

          {/* Note — always-open textarea, saves on blur */}
          <div>
            <Textarea
              value={memoValue}
              onChange={(e) => setMemoValue(e.target.value)}
              onBlur={() => {
                const next = memoValue.trim() || null;
                if (next !== (tx.memo ?? null)) patchTx.mutate({ memo: next });
              }}
              onKeyDown={(e) => {
                if (e.key === "Escape") { setMemoValue(tx.memo ?? ""); e.currentTarget.blur(); }
              }}
              placeholder="Add a note…"
              aria-label="Note"
              rows={3}
              className="resize-none"
            />
          </div>

          <div className="border-t" />

          <Button
            size="xs"
            variant="outline"
            onClick={() => setAutomating(true)}
            className="w-full"
          >
            <Zap size={12} />
            Create automation
          </Button>

          {automating && (
            <QuickAutomationModal tx={tx} onClose={() => setAutomating(false)} />
          )}

          <TransferTools tx={tx} />

          <TransactionTags tx={tx} />

          <div className="border-t" />

          {/* Fields */}
          <dl className="space-y-3 text-sm">
            <DescriptionField description={tx.description} engineId={searchEngine} />

            {/* Merchant — link to merchant page, pencil to edit */}
            <div className="flex items-center justify-between gap-2">
              <dt className="shrink-0 text-muted-foreground">Merchant</dt>
              {editingMerchant ? (
                <MerchantCombobox
                  value={tx.merchant_id ?? ""}
                  onChange={(id) => { patchTx.mutate({ merchant_id: id || null }); setEditingMerchant(false); }}
                  merchants={merchants}
                  placeholder="—"
                  className="flex-1"
                  inputClassName="w-full bg-transparent text-sm text-right placeholder:text-muted-foreground focus-visible:outline-none truncate"
                  autoFocus
                  onClose={() => setEditingMerchant(false)}
                />
              ) : (
                <div className="flex items-center gap-1.5 min-w-0">
                  {tx.merchant_id ? (
                    <button
                      onClick={() => { onClose(); navigate(`/merchants#id=${tx.merchant_id}`); }}
                      className="truncate rounded text-sm text-right hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                    >
                      {tx.merchant_name ?? "Unknown"}
                    </button>
                  ) : (
                    <span className="text-sm text-muted-foreground">—</span>
                  )}
                  <button
                    onClick={() => setEditingMerchant(true)}
                    className="shrink-0 rounded p-0.5 text-muted-foreground hover:bg-accent hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                    title="Edit merchant"
                    aria-label="Edit merchant"
                  >
                    <Pencil size={12} />
                  </button>
                </div>
              )}
            </div>

            {/* Category — links to category pages, pencil to edit */}
            {editingCategory ? (
              <div className="flex items-center justify-between gap-2">
                <dt className="shrink-0 text-muted-foreground">Category</dt>
                <CategoryCombobox
                  value={tx.category_id ?? ""}
                  onChange={(id) => { patchTx.mutate({ category_id: id || null }); setEditingCategory(false); }}
                  categories={categories}
                  placeholder="—"
                  className="flex-1"
                  inputClassName="w-full bg-transparent text-sm text-right placeholder:text-muted-foreground focus-visible:outline-none truncate"
                  autoFocus
                  onClose={() => setEditingCategory(false)}
                />
              </div>
            ) : (() => {
              const cat = categories.find((c) => c.id === tx.category_id) ?? null;
              const parent = cat?.parent_id ? categories.find((c) => c.id === cat.parent_id) ?? null : null;
              return (
                <>
                  {parent && (
                    <div className="flex items-center justify-between gap-2">
                      <dt className="shrink-0 text-muted-foreground">Category</dt>
                      <button
                        onClick={() => { onClose(); navigate(`/categories#id=${parent.id}`); }}
                        className="truncate rounded text-sm text-right hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                      >
                        {parent.name}
                      </button>
                    </div>
                  )}
                  <div className="flex items-center justify-between gap-2">
                    <dt className="shrink-0 text-muted-foreground">{parent ? "Subcategory" : "Category"}</dt>
                    <div className="flex items-center gap-1.5 min-w-0">
                      {cat ? (
                        <button
                          onClick={() => { onClose(); navigate(`/categories#id=${cat.id}`); }}
                          className="truncate rounded text-sm text-right hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                        >
                          {cat.name}
                        </button>
                      ) : (
                        <span className="text-sm text-muted-foreground">—</span>
                      )}
                      <button
                        onClick={() => setEditingCategory(true)}
                        className="shrink-0 rounded p-0.5 text-muted-foreground hover:bg-accent hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                        title="Edit category"
                        aria-label="Edit category"
                      >
                        <Pencil size={12} />
                      </button>
                    </div>
                  </div>
                </>
              );
            })()}

            {tx.account_name && (
              <div className="flex items-center justify-between gap-2 text-sm">
                <dt className="shrink-0 text-muted-foreground">Account</dt>
                <dd className="truncate">
                  {tx.account_id ? (
                    <button
                      onClick={() => { onClose(); navigate(`/accounts#id=${tx.account_id}`); }}
                      className="rounded hover:underline truncate focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                    >
                      {tx.account_name}
                    </button>
                  ) : (
                    tx.account_name
                  )}
                </dd>
              </div>
            )}
            <Field label="Transaction date" value={formatDate(tx.transaction_date)} />
            {tx.post_date && <Field label="Post date" value={formatDate(tx.post_date)} />}
            {tx.balance != null && <Field label="Balance after" value={formatCurrency(tx.balance)} />}

          </dl>

          <SimilarTransactions
            txId={tx.id}
            onOpen={(id) => { onClose(); navigate(`/transactions/${id}`); }}
          />
        </div>
      </div>
    </>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/** "Have I paid this before?" — every transaction sharing this one's
 *  descriptor (exactly, or near enough for pg_trgm), with the running total.
 *  Rows open the full detail page: a similar transaction is usually outside
 *  the table page currently loaded, so swapping the pane's selection would
 *  leave it with nothing to show. */
function SimilarTransactions({ txId, onOpen }: { txId: string; onOpen: (id: string) => void }) {
  const { data, isLoading } = useQuery(queries.similarTransactions(txId));

  if (isLoading || !data) return null;
  const rows = data.transactions ?? [];
  const total = data.total ?? rows.length;

  return (
    <div className="space-y-2">
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-xs font-medium text-muted-foreground">Similar transactions</p>
        {total > 0 && (
          <p className="text-xs tabular-nums text-muted-foreground">
            {total} · {formatCurrency(data.total_amount)}
          </p>
        )}
      </div>

      {total === 0 ? (
        <p className="text-xs text-muted-foreground">No others with this description.</p>
      ) : (
        <div className="overflow-hidden rounded-lg border bg-muted/30">
          {rows.map((s) => (
            <SimilarRow key={s.id} row={s} onOpen={() => onOpen(s.id)} />
          ))}
          {total > rows.length && (
            <p className="border-t px-2.5 py-1.5 text-caption text-muted-foreground">
              + {total - rows.length} more
            </p>
          )}
        </div>
      )}
    </div>
  );
}

function SimilarRow({ row, onOpen }: { row: SimilarTransaction; onOpen: () => void }) {
  return (
    <button
      onClick={onOpen}
      title={row.description ?? undefined}
      className="flex w-full items-center gap-2 border-b px-2.5 py-1.5 text-left text-xs last:border-b-0 transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
    >
      <span className="shrink-0 tabular-nums text-muted-foreground">{formatDate(row.transaction_date)}</span>
      {/* An exact match repeats the descriptor above it, so the date and the
          amount are all it needs. A near-match shows how it differs, marked
          with a ~ — that is the whole point of including it. */}
      {row.match === "similar" && (
        <span className="min-w-0 truncate text-muted-foreground">~ {row.description}</span>
      )}
      {/* The row is the lightweight serializer's shape — no source or
          transaction_type to hand amountColor, so money in is simply green. */}
      <span className={cn("ml-auto shrink-0 tabular-nums font-medium", row.amount > 0 && "text-positive")}>
        {formatCurrency(row.amount)}
      </span>
    </button>
  );
}

/** The description doubles as a web search: raw bank descriptors ("SQ *SOME
 *  SHOP 8005551234") are often the only way to work out what a charge was, and
 *  a search engine is where that gets resolved. Engine comes from
 *  Settings → Transactions. */
function DescriptionField({ description, engineId }: { description: string | null; engineId: string }) {
  const engine = searchEngineById(engineId);
  const query = (description ?? "").trim();

  if (!query) return <Field label="Description" value="—" />;

  return (
    <div className="flex justify-between gap-4">
      <dt className="shrink-0 text-muted-foreground">Description</dt>
      <dd className="min-w-0 text-right font-medium">
        <a
          href={searchUrl(engineId, query)}
          target="_blank"
          rel="noopener noreferrer"
          title={`Search ${engine.label} for "${query}"`}
          className="group inline-flex items-start gap-1 rounded text-right hover:text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          <span className="min-w-0">{description}</span>
          <Search
            size={11}
            aria-hidden
            className="mt-1 shrink-0 text-muted-foreground transition-colors group-hover:text-primary"
          />
        </a>
      </dd>
    </div>
  );
}

function Field({ label, value, onNavigate }: { label: string; value: string; onNavigate?: () => void }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-muted-foreground shrink-0">{label}</dt>
      <dd className="text-right font-medium">
        {onNavigate ? (
          <button onClick={onNavigate} className="rounded hover:underline hover:text-primary transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
            {value}
          </button>
        ) : value}
      </dd>
    </div>
  );
}
