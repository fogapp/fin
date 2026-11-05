import { useState, useEffect, useRef } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { TrendingUp, Plus, X, ChevronLeft } from "lucide-react";
import { useDebounced } from "@/hooks/useDebounced";
import { useHashParam } from "@/hooks/useHashParam";
import { useSyncPolling } from "@/hooks/useSyncPolling";
import { useMarketColumnPrefs } from "@/hooks/useMarketColumnPrefs";
import { SearchInput } from "@/components/SearchInput";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/PageState";
import { queries } from "@/api/queries";
import { cn, formatCurrency, moneyColor } from "@/lib/utils";
import { SecurityDetailContent } from "@/pages/SecurityDetail";
import { MarketOverview } from "@/components/market/MarketOverview";
import { TrendSparkline } from "@/components/market/TrendSparkline";
import { InstrumentClassChip, StalenessBadge } from "@/components/MarketBadges";
import { priceSourceLabel } from "@/lib/marketData";
import type { SecuritySummary, TickerSearchResult } from "@/api/types";
import type { MarketColumnPrefs } from "@/hooks/useMarketColumnPrefs";
import { invalidate, keys } from "@/api/keys";
import { useWatchSecurity } from "@/hooks/mutations/useWatchSecurity";

// Detail-route param. Ticker when present; otherwise the id, which the
// backend's find_by_param! accepts as a fallback.
function paramFor(s: SecuritySummary): string {
  return s.ticker ?? s.id;
}

export function Market() {
  const [rawId, setHashId] = useHashParam("id");
  const selectedTicker = rawId ?? null;
  const setSelectedTicker = (ticker: string | null) => setHashId(ticker);
  const { prefs } = useMarketColumnPrefs();

  const qc = useQueryClient();
  const [adding, setAdding] = useState(false);
  const [input, setInput] = useState("");
  const [search, setSearch] = useState("");
  const [syncing, setSyncing] = useState<string | null>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  useSyncPolling(syncing !== null, {
    delays: [3000, 8000, 20000],
    timeoutMs: 25000,
    onPoll: () => invalidate(qc, keys.securities),
    onStop: () => setSyncing(null),
  });

  // "/" focuses search
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "/" && document.activeElement?.tagName !== "INPUT" && document.activeElement?.tagName !== "TEXTAREA") {
        e.preventDefault();
        searchRef.current?.focus();
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const { data: securities = [], isLoading, isError, error, refetch } = useQuery(queries.securities());

  // Strictly the watchlist: everything the household has explicitly watched,
  // held or not. Holding a security says nothing about wanting it here.
  const watchlist = securities.filter((s) => s.watched);

  const q = search.trim().toUpperCase();
  const matchesQuery = (s: SecuritySummary) =>
    (s.ticker ?? "").toUpperCase().includes(q) || (s.name ?? "").toUpperCase().includes(q);
  // Exact ticker match beats prefix beats substring beats name-only, so
  // searching "NVDA" puts NVDA above NVDL and friends.
  const searchRank = (s: SecuritySummary) => {
    const t = (s.ticker ?? "").toUpperCase();
    if (t === q) return 0;
    if (t.startsWith(q)) return 1;
    if (t.includes(q)) return 2;
    return 3;
  };
  const byRank = (a: SecuritySummary, b: SecuritySummary) => searchRank(a) - searchRank(b);
  const filter = (list: SecuritySummary[]) => (q ? list.filter(matchesQuery).sort(byRank) : list);

  const { watch, unwatch } = useWatchSecurity({
    onWatched: (ticker) => {
      setSyncing(ticker);
      setInput("");
      setAdding(false);
    },
  });

  // Remote ticker lookup for anything the local list doesn't have — debounced
  // so we don't burn provider quota on every keystroke.
  const debouncedQ = useDebounced(search.trim(), 300);
  const remoteSearch = useQuery({
    ...queries.securitySearch(debouncedQ),
    enabled: debouncedQ.length >= 2,
  });
  const remoteResults = debouncedQ.length >= 2 ? remoteSearch.data?.results ?? [] : [];

  function trackRemote(result: TickerSearchResult) {
    watch.mutate(
      { ticker: result.ticker, name: result.name, instrument_class: result.instrument_class },
      { onSuccess: () => { setSelectedTicker(result.ticker); setSearch(""); } },
    );
  }

  function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    const ticker = input.trim().toUpperCase();
    if (!ticker) return;
    const existing = securities.find((s) => s.ticker === ticker);
    watch.mutate({ ticker, name: existing?.name ?? undefined });
  }

  // Only tickered securities can be watched, so suggestions require a ticker.
  const suggestions = input.trim()
    ? securities.filter((s) =>
        !s.watched && s.ticker != null &&
        (s.ticker.includes(input.toUpperCase()) || (s.name ?? "").toLowerCase().includes(input.toLowerCase()))
      ).slice(0, 6)
    : [];

  const filteredWatchlist = filter(watchlist);

  // Securities we already track but haven't watched — held positions and
  // known-but-unwatched rows. The remote lookup deliberately excludes known
  // tickers, so without this a search for a held ticker (e.g. NVDA) surfaced
  // only its lookalike derivatives.
  const trackedMatches = q
    ? securities
        .filter((s) => !s.watched && matchesQuery(s))
        .sort(byRank)
        .slice(0, 8)
    : [];

  return (
    <div className="flex h-full">
      {/* List column */}
      <div className={`flex-col border-r ${selectedTicker ? "hidden md:flex md:w-72" : "flex w-full md:w-72"}`}>
        <div className="flex h-14 items-center gap-2 border-b px-4">
          <SearchInput
            ref={searchRef}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Escape") setSearch(""); }}
            placeholder="Search securities…"
          />
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => setAdding((v) => !v)}
            className={cn("shrink-0 hover:text-foreground", adding ? "bg-accent text-foreground" : "text-muted-foreground")}
            title="Add to watchlist"
            aria-label="Add to watchlist"
          >
            <Plus size={16} />
          </Button>
        </div>

        {adding && (
          <form onSubmit={handleAdd} className="relative border-b px-3 py-2 flex items-center gap-2">
            <Input
              autoFocus
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ticker symbol…"
              aria-label="Ticker symbol"
              className="h-7 flex-1 px-2.5"
            />
            <Button type="submit" size="xs" disabled={!input.trim() || watch.isPending}>
              {watch.isPending ? "Adding…" : "Add"}
            </Button>
            {suggestions.length > 0 && (
              <div className="absolute top-full left-3 right-3 z-50 mt-0.5 rounded-lg border bg-card shadow-lg">
                {suggestions.map((s) => (
                  <button
                    key={s.ticker}
                    type="button"
                    onClick={() => { if (s.ticker) watch.mutate({ ticker: s.ticker, name: s.name ?? undefined }); }}
                    className="flex w-full items-center justify-between px-3 py-2 text-left text-sm hover:bg-accent transition-colors first:rounded-t-lg last:rounded-b-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
                  >
                    <span className="font-medium">{s.ticker}</span>
                    <span className="text-xs text-muted-foreground truncate ml-2">{s.name}</span>
                  </button>
                ))}
              </div>
            )}
          </form>
        )}

        <div className="flex-1 overflow-y-auto">
          {isLoading && (
            <div className="space-y-px p-2">
              {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-10 rounded-lg" />)}
            </div>
          )}

          {isError && !isLoading && (
            <ErrorState
              title="Failed to load securities"
              message={(error as Error)?.message}
              onRetry={() => refetch()}
            />
          )}

          {syncing && (
            <p className="px-4 py-1.5 text-tiny text-muted-foreground animate-pulse">
              Fetching prices for {syncing}…
            </p>
          )}

          {!isLoading && filteredWatchlist.map((s) => (
            <SecurityRow
              key={s.id}
              security={s}
              selected={paramFor(s) === selectedTicker}
              prefs={prefs}
              onClick={() => setSelectedTicker(paramFor(s) === selectedTicker ? null : paramFor(s))}
              onRemove={() => { if (s.ticker) unwatch.mutate(s.ticker); }}
            />
          ))}

          {/* Tracked securities outside the watchlist (held positions,
              unwatched rows) — clicking opens the detail pane */}
          {!isLoading && trackedMatches.length > 0 && (
            <div className="border-t">
              <p className="px-4 pt-3 pb-1 text-caption font-semibold tracking-tight">Already tracked</p>
              {trackedMatches.map((s) => (
                <SecurityRow
                  key={s.id}
                  security={s}
                  selected={paramFor(s) === selectedTicker}
                  prefs={prefs}
                  onClick={() => setSelectedTicker(paramFor(s) === selectedTicker ? null : paramFor(s))}
                />
              ))}
            </div>
          )}

          {!isLoading && !isError && watchlist.length === 0 && !q && (
            <EmptyState
              icon={TrendingUp}
              title="No securities yet"
              description="Add a ticker to start tracking."
              className="py-16"
            />
          )}

          {!isLoading && q && filteredWatchlist.length === 0 && trackedMatches.length === 0 && remoteResults.length === 0 && !remoteSearch.isFetching && (
            <EmptyState title="No securities match the current filters." className="py-6" />
          )}

          {/* Remote lookup — tickers not tracked yet, added on click */}
          {q.length >= 2 && (remoteResults.length > 0 || remoteSearch.isFetching) && (
            <div className="border-t pb-1.5">
              <p className="px-4 pt-3 text-caption font-semibold tracking-tight">Not in your list</p>
              {remoteSearch.isFetching && (
                <p className="px-4 py-1.5 text-tiny text-muted-foreground animate-pulse">Searching markets…</p>
              )}
              {remoteResults.map((r) => (
                <button
                  key={r.ticker}
                  type="button"
                  onClick={() => trackRemote(r)}
                  disabled={watch.isPending}
                  className="group flex w-full items-center gap-2 px-4 py-2 text-left text-sm transition-colors hover:bg-accent disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
                >
                  <span className="font-medium shrink-0">{r.ticker}</span>
                  <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">{r.name}</span>
                  <span className="shrink-0 text-tiny uppercase tracking-wider text-muted-foreground">
                    {r.security_type}
                  </span>
                  <Plus size={13} className="shrink-0 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100" />
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Detail pane */}
      <div className={`flex-col overflow-y-auto ${selectedTicker ? "flex flex-1" : "hidden md:flex md:flex-1"}`}>
        {selectedTicker ? (
          <>
            <button
              onClick={() => setSelectedTicker(null)}
              className="flex h-11 items-center gap-1.5 border-b px-4 text-sm text-muted-foreground hover:text-foreground md:hidden focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
            >
              <ChevronLeft size={16} />
              Market
            </button>
            <SecurityDetailContent id={selectedTicker} />
          </>
        ) : (
          <MarketOverview onSelect={(param) => setSelectedTicker(param)} />
        )}
      </div>
    </div>
  );
}

function SecurityRow({ security: s, selected, prefs, onClick, onRemove }: {
  security: SecuritySummary;
  selected: boolean;
  prefs: MarketColumnPrefs;
  onClick: () => void;
  onRemove?: () => void;
}) {
  const primaryText = (prefs.primary === "ticker" ? s.ticker ?? s.name : s.name ?? s.ticker) ?? "—";

  const subtitleText =
    prefs.subtitle === "none"   ? null :
    prefs.subtitle === "ticker" ? s.ticker :
    prefs.subtitle === "type"   ? (s.security_type ?? null) :
    s.name;

  const value1Text =
    prefs.value1 === "none"         ? null :
    prefs.value1 === "market_value" ? (s.market_value > 0 ? formatCurrency(s.market_value, true) : null) :
    s.latest_price                  ? formatCurrency(s.latest_price.close) : null;

  const value2 =
    prefs.value2 === "ytd_change" ? s.ytd_change_pct :
    prefs.value2 === "day_change" ? s.day_change_pct :
    null;

  return (
    <button
      onClick={onClick}
      className={cn(
        "group flex w-full items-center justify-between px-4 py-2 text-left text-sm transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
        selected && "bg-primary/8 text-primary"
      )}
    >
      <div className="min-w-0">
        <p className="flex items-center gap-1.5 font-medium leading-tight">
          <span className="truncate">{primaryText}</span>
          {/* The sparkline already competes for row width — the class chip
              yields to it (instrument type stays available as a subtitle). */}
          {!prefs.sparkline && <InstrumentClassChip instrumentClass={s.instrument_class} />}
        </p>
        {subtitleText && (
          <p className="text-caption text-muted-foreground truncate max-w-28 leading-tight">{subtitleText}</p>
        )}
      </div>
      <div className="ml-2 shrink-0 flex items-center gap-1.5">
        <StalenessBadge price={s.latest_price} />
        {prefs.sparkline && s.spark.length > 1 && (
          <TrendSparkline data={s.spark} width={44} height={16} className="shrink-0" />
        )}
        <div className="text-right">
          {value1Text && (
            <p
              className="text-xs tabular-nums leading-tight"
              title={s.latest_price ? priceSourceLabel(s.latest_price.source) : undefined}
            >
              {value1Text}
            </p>
          )}
          {value2 != null && (
            <p className={cn("text-tiny tabular-nums font-medium leading-tight", moneyColor(value2))}>
              {value2 >= 0 ? "+" : ""}{value2.toFixed(2)}%
            </p>
          )}
        </div>
        {onRemove && (
          <span
            role="button"
            tabIndex={0}
            aria-label={`Remove ${s.ticker ?? s.name ?? "security"} from watchlist`}
            onClick={(e) => { e.stopPropagation(); onRemove(); }}
            onKeyDown={(e) => e.key === "Enter" && (e.stopPropagation(), onRemove())}
            className="rounded p-0.5 text-destructive opacity-0 transition-opacity hover:bg-destructive/10 group-hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <X size={12} />
          </span>
        )}
      </div>
    </button>
  );
}
