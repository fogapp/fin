import { api } from "./client";
import type {
  BudgetLine, BudgetLineMode, BudgetPeriod, BudgetPeriodKind, CashTransaction, ReconciliationAcceptResult, WorkflowRunRevertResult,
} from "./types";

/** Named writes, kept apart from `queries` so that module only holds read
 *  options. One-off writes can stay inline next to their component. */
export const mutations = {
  /** Set a category's budget from `month` on (mode "ongoing", the default)
   *  or for that month alone ("month_only"). Omitted fields keep the plan's
   *  current values. */
  setBudgetLine: (body: {
    month: string;
    category_id: string;
    planned?: number;
    rollover?: boolean;
    period?: BudgetPeriodKind;
    mode?: BudgetLineMode;
  }) =>
    api.put<BudgetLine>("/budget/line", body),
  /** Stop budgeting a category from `month` on — or, with month_only, drop
   *  just that month's one-month amount. */
  stopBudgetLine: (body: { month: string; category_id: string; month_only?: boolean }) =>
    api.delete<void>("/budget/line", body),
  /** Income target and/or the "everything else" amount, from `month` on;
   *  null clears. */
  setBudgetPeriod: (body: { month: string; income_planned?: number | null; other_planned?: number | null }) =>
    api.put<BudgetPeriod>("/budget/period", body),
  /** Start a plan from the few categories that make up most spending. */
  budgetAutofill: (body: { month: string }) =>
    api.post<{ filled: number }>("/budget/autofill", body),
  setBudgetExcluded: (id: string, budget_excluded: boolean) =>
    api.patch<CashTransaction>(`/cash_transactions/${id}`, { budget_excluded }),

  dismissAllIssues: (source?: string) =>
    api.post<{ dismissed: number }>("/issues/dismiss_all", source ? { source } : {}),
  acceptReconciliation: (key: string) =>
    api.post<ReconciliationAcceptResult>("/reconciliation/accept", { key }),
  acceptAllReconciliation: () => api.post<{ status: string }>("/reconciliation/accept_all", {}),

  revertWorkflowRun: (id: string) => api.post<WorkflowRunRevertResult>(`/workflow_runs/${id}/revert`, {}),
  revertWorkflowRuns: (workflowId: string, since?: string) =>
    api.post<{ status: string }>(`/workflows/${workflowId}/revert_runs`, since ? { since } : {}),
};
