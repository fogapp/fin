/**
 * Drill-down link builder: every chart's `linkFor` should return URLs built
 * with `transactionsHref` so clicks land on a pre-filtered /transactions table.
 */

export interface TransactionsHrefParams {
  /** ISO dates (inclusive). Ignored when `month` is given. */
  from?: string;
  to?: string;
  /** "YYYY-MM" — expands to that month's start/end dates. */
  month?: string;
  categoryId?: string;
  /** Multiple categories (e.g. a parent group and its children) — scopes the
   *  transactions query server-side rather than becoming a pill. */
  categoryIds?: string[];
  merchantId?: string;
  tagId?: string;
  /** Drops rows carrying any of these tags — server-side, like categoryIds. */
  excludeTagIds?: string[];
  accountId?: string;
  source?: string;
}

/** First/last day of a "YYYY-MM" month as ISO dates. */
export function monthDateRange(month: string): { from: string; to: string } {
  const [y, m] = month.split("-").map(Number);
  const last = new Date(y, m, 0).getDate();
  return { from: `${month}-01`, to: `${month}-${String(last).padStart(2, "0")}` };
}

export function transactionsHref(params: TransactionsHrefParams): string {
  const q = new URLSearchParams();
  const range = params.month ? monthDateRange(params.month.slice(0, 7)) : { from: params.from, to: params.to };
  if (range.from) q.set("start_date", range.from);
  if (range.to) q.set("end_date", range.to);
  if (params.categoryId) q.set("category_id", params.categoryId);
  if (params.categoryIds?.length) q.set("category_ids", params.categoryIds.join(","));
  if (params.merchantId) q.set("merchant_id", params.merchantId);
  if (params.tagId) q.set("tag_id", params.tagId);
  if (params.excludeTagIds?.length) q.set("exclude_tag_ids", params.excludeTagIds.join(","));
  if (params.accountId) q.set("account_id", params.accountId);
  if (params.source) q.set("source", params.source);
  const qs = q.toString();
  return qs ? `/transactions?${qs}` : "/transactions";
}
