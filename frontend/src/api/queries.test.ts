import { describe, it, expect, beforeEach, vi } from "vitest";

vi.mock("./client", () => ({
  api: {
    get: vi.fn(),
    post: vi.fn(),
    patch: vi.fn(),
    delete: vi.fn(),
  },
}));

import { api } from "./client";
import { queries } from "./queries";
import { mutations } from "./mutations";

const apiMock = vi.mocked(api);

beforeEach(() => {
  apiMock.get.mockReset();
  apiMock.post.mockReset();
  apiMock.delete.mockReset();
  apiMock.get.mockResolvedValue(undefined as never);
  apiMock.post.mockResolvedValue(undefined as never);
  apiMock.delete.mockResolvedValue(undefined as never);
});

describe("queries — thin wrappers (path + queryKey)", () => {
  it.each([
    [ "me",                   queries.me(),                  ["me"],                  "/me"          ],
    [ "households",           queries.households(),          ["households"],          "/households"  ],
    [ "accounts",             queries.accounts(),            ["accounts"],            "/accounts"    ],
    [ "brokers",              queries.brokers(),             ["brokers"],             "/brokers"     ],
    [ "categories",           queries.categories(),          ["categories"],          "/categories"  ],
    [ "merchants",            queries.merchants(),           ["merchants"],           "/merchants"   ],
    [ "tags",                 queries.tags(),                ["tags"],                "/tags"        ],
    [ "savedViews",           queries.savedViews(),          ["saved_views"],         "/saved_views"              ],
    [ "transferCandidates",   queries.transferCandidates(),  ["transfers", "candidates"], "/transfers/candidates" ],
    [ "buys",                 queries.buys(),                ["buys", { from: null, to: null }],      "/buys"        ],
    [ "sells",                queries.sells(),               ["sells", { from: null, to: null }, null],     "/sells"       ],
    [ "dividends",            queries.dividends(),           ["dividends", { from: null, to: null }, null], "/dividends"   ],
    [ "portfolio",            queries.portfolio(),           ["portfolio"],           "/portfolio"   ],
    [ "cashflow",             queries.cashflow(),            ["cashflow", { from: null, to: null, account_id: null, tag_id: null, exclude_tag_ids: null, category_id: null, merchant_id: null, dimension: null }],  "/cashflow"    ],
    [ "subscriptions",        queries.subscriptions(),       ["subscriptions", "list", "active"], "/subscriptions?status=active" ],
    [ "costBasis",            queries.costBasis(),           ["cost_basis"],          "/cost_basis"  ],
    [ "securities",           queries.securities(),          ["securities"],          "/market"      ],
    [ "benchmarks",           queries.benchmarks(),          ["benchmarks"],          "/benchmarks"  ],
  ])("%s hits %s with stable queryKey", async (_name, q: { queryKey: readonly unknown[]; queryFn: (ctx: never) => unknown }, key, path) => {
    expect(q.queryKey).toEqual(key);
    await q.queryFn({ queryKey: q.queryKey } as never);
    expect(apiMock.get).toHaveBeenCalledWith(path);
  });
});

describe("queries — parameterised paths", () => {
  it("transaction(id) hits /cash_transactions/:id", async () => {
    const q = queries.transaction("tx-1");
    await q.queryFn({ queryKey: q.queryKey } as never);
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions/tx-1");
  });

  it("accountTransactions(id) and merchantTransactions(id) include filter params", async () => {
    await queries.accountTransactions("acc-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?account_id=acc-1");

    await queries.merchantTransactions("m-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?merchant_id=m-1");
  });

  it("accountBalanceSnapshots, investmentLots, accountInvestmentTransactions", async () => {
    await queries.accountBalanceSnapshots("acc-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/accounts/acc-1/balance_snapshots");

    await queries.investmentLots("sec-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/investment_lots?security_id=sec-1");

    await queries.accountInvestmentTransactions("acc-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/investment_transactions?account_id=acc-1");
  });

  it("security, securityNews, benchmarkPrices", async () => {
    await queries.security("AAPL").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/market/AAPL");
    await queries.securityNews("AAPL").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/market/AAPL/news");
    await queries.benchmarkPrices("SPY").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/benchmarks/SPY");
  });

  it("category, merchant, tag, tagTransactions", async () => {
    await queries.category("cat-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/categories/cat-1");
    await queries.merchant("m-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/merchants/m-1");
    await queries.tag("t-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/tags/t-1");
    await queries.tagTransactions("t-1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?tag_id=t-1");
  });
});

describe("queries — conditional query strings", () => {
  it("dashboard() with no brokerId omits the broker_id param", async () => {
    await queries.dashboard().queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/dashboard");
  });

  it("dashboard(42) includes ?broker_id=42", async () => {
    await queries.dashboard(42).queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/dashboard?broker_id=42");
  });

  it("transactions({}) omits the query string entirely", async () => {
    await queries.transactions({}).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions", { signal: undefined });
  });

  it("transactions({tag_id:'1'}) URL-encodes filters", async () => {
    await queries.transactions({ tag_id: "1", foo: "a b" }).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?tag_id=1&foo=a+b", { signal: undefined });
  });

  it("categoryTransactions takes a single string", async () => {
    await queries.categoryTransactions("c1").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?category_id=c1");
  });

  it("categoryTransactions takes an array (uses category_ids=…)", async () => {
    await queries.categoryTransactions([ "c1", "c2", "c3" ]).queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions?category_ids=c1,c2,c3");
  });

  it("pendingTransfer composes both query params", async () => {
    await queries.pendingTransfer("tx-1", "CashTransaction").queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith(
      "/transfers/for_transaction?transaction_id=tx-1&transaction_type=CashTransaction",
    );
  });

  it("transferSearch is disabled by default and includes the transaction id", async () => {
    const q = queries.transferSearch("tx-1");
    expect(q.enabled).toBe(false);
    await q.queryFn({} as never);
    expect(apiMock.get).toHaveBeenCalledWith("/cash_transactions/transfer_search?transaction_id=tx-1", { signal: undefined });
  });

  const NO_SCOPE = { account_id: null, tag_id: null, exclude_tag_ids: null, category_id: null, merchant_id: null, dimension: null };

  it("cashflow({from,to}) appends the range and keys on it", async () => {
    const q = queries.cashflow({ from: "2026-01-01", to: "2026-07-03" });
    expect(q.queryKey).toEqual(["cashflow", { from: "2026-01-01", to: "2026-07-03", ...NO_SCOPE }]);
    await q.queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/cashflow?from=2026-01-01&to=2026-07-03");
  });

  it("cashflowSpendBreakdown({from,to}) hits /cashflow/spend_breakdown and keys on the range", async () => {
    const q = queries.cashflowSpendBreakdown({ from: "2026-01-01", to: "2026-07-03" });
    expect(q.queryKey).toEqual(["cashflow", "spend_breakdown", { from: "2026-01-01", to: "2026-07-03", ...NO_SCOPE }]);
    await q.queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/cashflow/spend_breakdown?from=2026-01-01&to=2026-07-03");
  });

  it("cashflowSankey({from}) hits /cashflow/sankey with only the given bound", async () => {
    await queries.cashflowSankey({ from: "2026-01-01" }).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/cashflow/sankey?from=2026-01-01");
  });

  it("cashflow scope params (account/tag/category/dimension) reach the URL and the key", async () => {
    const q = queries.cashflowSankey({
      from: "2026-01-01", account_id: "a1", tag_id: "t1", category_id: "c1", dimension: "merchant",
    });
    expect(q.queryKey).toEqual(["cashflow", "sankey", {
      from: "2026-01-01", to: null, account_id: "a1", tag_id: "t1", exclude_tag_ids: null, category_id: "c1", merchant_id: null, dimension: "merchant",
    }]);
    await q.queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/cashflow/sankey?from=2026-01-01&account_id=a1&tag_id=t1&category_id=c1&dimension=merchant");
  });

  it("cashflow exclude_tag_ids joins into one param and keys order-independently", async () => {
    const q = queries.cashflow({ exclude_tag_ids: ["t2", "t1"] });
    expect(q.queryKey).toEqual(queries.cashflow({ exclude_tag_ids: ["t1", "t2"] }).queryKey);
    expect(q.queryKey[1]).toMatchObject({ exclude_tag_ids: "t1,t2" });
    await q.queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/cashflow?exclude_tag_ids=t2%2Ct1");
  });

  it("savedReports lists /saved_reports", async () => {
    const q = queries.savedReports();
    expect(q.queryKey).toEqual(["saved_reports"]);
    await q.queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/saved_reports");
  });

  it("review(month) keys on the month and appends it", async () => {
    const q = queries.review("2026-07");
    expect(q.queryKey).toEqual(["review", "2026-07"]);
    await q.queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/review?month=2026-07");
  });

  it("subscriptionsCalendar(month) nests under the subscriptions key prefix", async () => {
    const q = queries.subscriptionsCalendar("2026-08");
    expect(q.queryKey).toEqual(["subscriptions", "calendar", "2026-08"]);
    await q.queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/subscriptions/calendar?month=2026-08");
  });

  it("buys/sells/dividends/crypto accept a range", async () => {
    await queries.buys({ from: "2026-04-03", to: "2026-07-03" }).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/buys?from=2026-04-03&to=2026-07-03");
    await queries.crypto({ to: "2026-07-03" }).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/crypto?to=2026-07-03");
  });
});

describe("queries — workflow runs", () => {
  it("workflowRunGroups GETs grouped runs, composing workflow/status/page filters", async () => {
    await queries.workflowRunGroups({ workflowId: "w1", status: "failed", page: 2 }).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/workflow_runs?workflow_id=w1&status=failed&grouped=true&page=2");
  });

  it("workflowRuns includes trace_id only when given", async () => {
    await queries.workflowRuns({ workflowId: "w1", traceId: "t4" }).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/workflow_runs?workflow_id=w1&trace_id=t4&page=1");

    await queries.workflowRuns({ workflowId: "w1" }).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/workflow_runs?workflow_id=w1&page=1");
  });
});

describe("queries — activity groups", () => {
  it("activityGroups GETs grouped activity, composing source/severity/page filters", async () => {
    await queries.activityGroups({ source: "workflow", severity: "error", page: 2 }).queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/activity?source=workflow&severity=error&grouped=true&page=2");

    await queries.activityGroups().queryFn();
    expect(apiMock.get).toHaveBeenCalledWith("/activity?grouped=true&page=1");
  });
});

describe("mutations", () => {
  it("revertWorkflowRun POSTs /workflow_runs/:id/revert with empty body", () => {
    mutations.revertWorkflowRun("r1");
    expect(apiMock.post).toHaveBeenCalledWith("/workflow_runs/r1/revert", {});
  });

  it("revertWorkflowRuns POSTs /workflows/:id/revert_runs, including since only when given", () => {
    mutations.revertWorkflowRuns("w1");
    expect(apiMock.post).toHaveBeenCalledWith("/workflows/w1/revert_runs", {});

    mutations.revertWorkflowRuns("w1", "2026-07-01T00:00:00Z");
    expect(apiMock.post).toHaveBeenCalledWith("/workflows/w1/revert_runs", { since: "2026-07-01T00:00:00Z" });
  });

  it("acceptReconciliation POSTs the issue key verbatim", () => {
    mutations.acceptReconciliation("reconciliation:a1:s1");
    expect(apiMock.post).toHaveBeenCalledWith("/reconciliation/accept", { key: "reconciliation:a1:s1" });
  });

  it("acceptAllReconciliation POSTs with an empty body", () => {
    mutations.acceptAllReconciliation();
    expect(apiMock.post).toHaveBeenCalledWith("/reconciliation/accept_all", {});
  });

  it("dismissAllIssues POSTs /issues/dismiss_all, including source only when given", () => {
    mutations.dismissAllIssues();
    expect(apiMock.post).toHaveBeenCalledWith("/issues/dismiss_all", {});

    mutations.dismissAllIssues("system_audit");
    expect(apiMock.post).toHaveBeenCalledWith("/issues/dismiss_all", { source: "system_audit" });
  });
});

describe("queries — staleTime overrides", () => {
  it("preferences holds forever (staleTime: Infinity)", () => {
    expect(queries.preferences().staleTime).toBe(Infinity);
  });

  it("about holds forever too", () => {
    expect(queries.about().staleTime).toBe(Infinity);
  });
});
