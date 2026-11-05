import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { Landmark, Upload, ChevronRight, ChevronDown, Pencil, RefreshCw, CreditCard } from "lucide-react";
import { MasterDetailShell } from "@/components/MasterDetailShell";
import { PageHeader } from "@/components/layout/PageHeader";
import { NewAccountForm } from "@/components/NewAccountForm";
import { CsvUploadModal } from "@/components/CsvUploadModal";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { StatRibbon } from "@/components/StatRibbon";
import { ResponsiveTransactionView as TransactionTable } from "@/components/TransactionList";
import { InvestmentTransactionTable } from "@/components/InvestmentTransactionTable";
import { HoldingsTable, type HoldingRow } from "@/components/HoldingsTable";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import { Select } from "@/components/ui/select";
import { Field } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/empty-state";
import { ChartLabel, LineChart } from "@/components/charts";
import { SpendChartCard } from "@/components/spend-chart";
import { formatCurrency, formatDate } from "@/lib/utils";
import type { Account, AccountWithStats } from "@/api/types";
import { invalidate, keys } from "@/api/keys";
// InvestmentTransaction type used via queries.accountInvestmentTransactions

export function Accounts() {
  const COLLAPSED_KEY = "acct_collapsed_brokers";
  const [collapsedBrokers, setCollapsedBrokers] = useState<Set<string>>(() => {
    try { return new Set(JSON.parse(sessionStorage.getItem(COLLAPSED_KEY) ?? "[]")); }
    catch { return new Set(); }
  });
  function toggleBroker(broker: string) {
    setCollapsedBrokers((prev) => {
      const next = new Set(prev);
      if (next.has(broker)) next.delete(broker);
      else next.add(broker);
      sessionStorage.setItem(COLLAPSED_KEY, JSON.stringify([...next]));
      return next;
    });
  }

  const { data: accounts = [], isLoading, isError, refetch } = useQuery(queries.accounts());

  // Group by broker when not searching
  const byBroker = accounts.reduce<Record<string, AccountWithStats[]>>((acc, a) => {
    (acc[a.broker_name ?? "No broker"] ??= []).push(a);
    return acc;
  }, {});

  return (
    <MasterDetailShell
      title="Accounts"
      noun="account"
      nounPlural="accounts"
      icon={Landmark}
      items={accounts}
      isLoading={isLoading}
      isError={isError}
      refetch={refetch}
      // A dialog (link a bank or enter one by hand) rather than an inline form.
      renderNewForm={({ onCreated, onCancel }) => (
        <NewAccountForm onClose={onCancel} onCreated={(a) => onCreated(a.id)} />
      )}
      renderListBody={({ filtered, highlightedIndex, isSearching, selectedId, toggleSelected }) =>
        isSearching ? (
          <>
            {filtered.map((a, i) => (
              <AccountRow key={a.id} account={a} selected={a.id === selectedId}
                highlighted={i === highlightedIndex}
                onClick={() => toggleSelected(a.id)} />
            ))}
            {filtered.length === 0 && (
              <p className="px-4 py-6 text-center text-xs text-muted-foreground">No accounts match</p>
            )}
          </>
        ) : (
          Object.entries(byBroker).map(([broker, brokerAccounts]) => {
            const collapsed = collapsedBrokers.has(broker);
            return (
              <div key={broker}>
                <button
                  onClick={() => toggleBroker(broker)}
                  className="flex w-full items-center gap-1 px-3 pb-1 pt-3 text-left hover:text-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-inset"
                >
                  {collapsed
                    ? <ChevronRight size={10} className="shrink-0 text-muted-foreground" />
                    : <ChevronDown size={10} className="shrink-0 text-muted-foreground" />}
                  <span className="text-tiny font-semibold uppercase tracking-wider text-muted-foreground">
                    {broker}
                  </span>
                </button>
                {!collapsed && brokerAccounts.map((a) => (
                  <AccountRow key={a.id} account={a} selected={a.id === selectedId}
                    onClick={() => toggleSelected(a.id)} />
                ))}
              </div>
            );
          })
        )
      }
      renderDetail={(id) => <AccountDetail id={id} accounts={accounts} />}
    />
  );
}

function AccountRow({ account, selected, highlighted = false, onClick }: {
  account: AccountWithStats; selected: boolean; highlighted?: boolean; onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex w-full items-center justify-between px-4 py-3 text-left text-sm transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-inset
        ${selected ? "bg-primary/8 text-primary" : ""}
        ${highlighted && !selected ? "bg-accent" : ""}`}
    >
      <div className="min-w-0">
        <p className="truncate font-medium">{account.name}</p>
        <p className="text-xs text-muted-foreground">
          {account.account_type && <span className="capitalize">{account.account_type}</span>}
          {account.account_type && account.account_number && <span> · </span>}
          {account.account_number && (
            <span className="font-mono">····{account.account_number.slice(-4)}</span>
          )}
        </p>
      </div>
      {(account.balance_usd != null || account.balance != null || account.portfolio_value > 0) && (
        <span className="ml-2 shrink-0 text-xs text-muted-foreground">
          {formatCurrency(account.balance_usd ?? account.balance ?? account.portfolio_value, true)}
        </span>
      )}
    </button>
  );
}

function AccountDetail({ id, accounts }: { id: string; accounts: AccountWithStats[] }) {
  const account = accounts.find((a) => a.id === id);
  const navigate = useNavigate();
  const { data: transactions = [], isLoading: txLoading } = useQuery(queries.accountTransactions(id));
  const { data: investmentTxns = [], isLoading: invLoading } = useQuery({
    ...queries.accountInvestmentTransactions(id),
    enabled: (account?.investment_transaction_count ?? 0) > 0,
  });
  const { data: balanceSnapshots = [] } = useQuery({
    ...queries.accountBalanceSnapshots(id),
    enabled: account?.balance != null,
  });
  const { data: holdingsData, isLoading: holdingsLoading } = useQuery({
    ...queries.accountHoldings(id),
    enabled: (account?.portfolio_value ?? 0) > 0,
  });
  const [showUpload, setShowUpload] = useState(false);
  const [monthFilter, setMonthFilter] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [balanceEditing, setBalanceEditing] = useState(false);
  const [balanceDraft, setBalanceDraft] = useState("");
  const [currencyDraft, setCurrencyDraft] = useState("USD");
  const [balanceUsdDraft, setBalanceUsdDraft] = useState("");
  const qc = useQueryClient();

  const updateAccount = useMutation({
    mutationFn: (patch: { name?: string; account_number?: string; account_type?: string; balance?: number | null; hidden?: boolean; tax_treatment?: string }) =>
      api.patch(`/accounts/${id}`, patch),
    onSuccess: () => { invalidate(qc, keys.accounts); setEditing(false); },
  });

  const updateBalance = useMutation({
    mutationFn: (patch: { balance: number | null; balance_currency: string; balance_usd: number | null }) =>
      api.patch(`/accounts/${id}`, patch),
    onSuccess: () => { invalidate(qc, keys.accounts); setBalanceEditing(false); },
  });

  const syncPlaid = useMutation({
    mutationFn: () => api.post(`/plaid/items/${account?.plaid_item_id}/sync`),
    onSuccess: () => {
      invalidate(qc, keys.accounts, keys.cashTransactions);
    },
  });

  function startBalanceEdit() {
    setBalanceDraft(account?.balance != null ? String(account.balance) : "");
    setCurrencyDraft(account?.balance_currency ?? "USD");
    setBalanceUsdDraft(account?.balance_usd != null ? String(account.balance_usd) : "");
    setBalanceEditing(true);
  }

  function commitBalance(e: React.FormEvent) {
    e.preventDefault();
    const balance = balanceDraft.trim() === "" ? null : parseFloat(balanceDraft);
    const currency = currencyDraft.trim().toUpperCase() || "USD";
    // The separate USD input is only shown for non-USD currencies. For USD the
    // USD value is the balance itself — the pre-filled draft may be stale.
    const rawUsd = balanceUsdDraft.trim();
    const balance_usd = currency === "USD" ? balance : rawUsd === "" ? null : parseFloat(rawUsd);
    updateBalance.mutate({ balance, balance_currency: currency, balance_usd });
  }
  if (!account) return null;

  return (
    <div className="flex flex-col">
      {showUpload && (
        <CsvUploadModal
          accountId={id}
          accountName={account.name}
          onClose={() => setShowUpload(false)}
        />
      )}

      {/* Header */}
      <PageHeader
        level={2}
        title={account.name}
        subtitle={account.broker_name ?? undefined}
        actions={[
          { label: editing ? "Stop editing" : "Edit account", icon: Pencil, onSelect: () => setEditing((e) => !e) },
          ...(account.plaid_item_id ? [ {
            label: syncPlaid.isPending ? "Syncing…" : "Sync from Plaid",
            icon: RefreshCw,
            onSelect: () => syncPlaid.mutate(),
            disabled: syncPlaid.isPending,
          } ] : []),
          { label: "Import transactions", icon: Upload, onSelect: () => setShowUpload(true) },
          ...(account.linked_loan_id == null ? [ {
            label: "Set up as loan",
            icon: CreditCard,
            onSelect: () => navigate(`/loans?account_id=${account.id}&name=${encodeURIComponent(account.name)}`),
          } ] : []),
        ]}
      >
        {account.account_type && (
          <Badge variant="outline" className="capitalize text-xs">{account.account_type}</Badge>
        )}
      </PageHeader>

      {editing && (
        <AccountEditForm
          account={account}
          saving={updateAccount.isPending}
          onSave={(patch) => updateAccount.mutate(patch)}
          onCancel={() => setEditing(false)}
        />
      )}

      {/* Balance display */}
      <div className="border-b px-6 py-4">
        <p className="text-xs text-muted-foreground mb-1">Balance</p>
        {balanceEditing ? (
          <form onSubmit={commitBalance} className="flex flex-wrap items-center gap-2">
            <Input
              autoFocus
              type="number"
              step="any"
              value={balanceDraft}
              onChange={(e) => setBalanceDraft(e.target.value)}
              placeholder="Amount"
              aria-label="Balance amount"
              className="w-32 tabular-nums [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
            />
            <Input
              value={currencyDraft}
              onChange={(e) => setCurrencyDraft(e.target.value.toUpperCase())}
              placeholder="USD"
              maxLength={10}
              aria-label="Currency"
              className="w-20 font-mono uppercase"
            />
            {currencyDraft.trim().toUpperCase() !== "USD" && (
              <Input
                type="number"
                step="any"
                value={balanceUsdDraft}
                onChange={(e) => setBalanceUsdDraft(e.target.value)}
                placeholder="USD value"
                aria-label="USD value"
                className="w-32 tabular-nums [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
              />
            )}
            <Button type="button" variant="ghost" size="sm" onClick={() => setBalanceEditing(false)}
              className="text-muted-foreground hover:text-foreground">
              Cancel
            </Button>
            <Button type="submit" size="sm" disabled={updateBalance.isPending}>
              {updateBalance.isPending ? "Saving…" : "Save"}
            </Button>
          </form>
        ) : (
          <button onClick={startBalanceEdit} className="group flex items-center gap-2 rounded-lg hover:opacity-80 transition-opacity focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
            <span className="text-2xl font-semibold tabular-nums">
              {account.balance != null ? (
                <>
                  {account.balance_currency !== "USD" && (
                    <span className="text-base text-muted-foreground mr-1">
                      {account.balance.toLocaleString()} {account.balance_currency}
                      {account.balance_usd != null && <span className="mx-1">·</span>}
                    </span>
                  )}
                  {account.balance_usd != null ? formatCurrency(account.balance_usd) : account.balance_currency === "USD" ? formatCurrency(account.balance) : null}
                </>
              ) : <span className="text-muted-foreground">—</span>}
            </span>
            <Pencil size={13} className="text-muted-foreground" />
          </button>
        )}
      </div>

      <StatRibbon borderTop={false} stats={[
        ...(account.portfolio_value > 0 ? [{ label: "Portfolio Value", value: formatCurrency(account.portfolio_value, true) }] : []),
        { label: "Cash Txns", value: account.cash_transaction_count.toLocaleString() },
        { label: "Investment Txns", value: account.investment_transaction_count.toLocaleString() },
        ...(account.latest_transaction_date ? [{ label: "Last Activity", value: formatDate(account.latest_transaction_date) }] : []),
      ]} />

      <div className="space-y-6 p-6">
        {account.account_number && (
          <p className="text-xs text-muted-foreground">
            Account number: <span className="font-mono">{account.account_number}</span>
          </p>
        )}

        {/* Balance history chart */}
        {balanceSnapshots.length > 1 && (
          <div>
            <ChartLabel>Balance History</ChartLabel>
            <LineChart
              data={balanceSnapshots}
              series={[{
                key: balanceSnapshots.some(s => s.balance_usd != null) ? "balance_usd" : "balance",
                label: "Balance",
              }]}
              xKey="date"
              height={160}
              area
            />
          </div>
        )}

        {/* Monthly spend chart — canonical card, account-scoped; clicking a
            month toggles the transaction table's month filter below. */}
        {account.cash_transaction_count > 0 && (
          <div>
            <ChartLabel>Monthly Spend</ChartLabel>
            <SpendChartCard
              variant="compact"
              scope={{ accountId: id }}
              height={160}
              onSelectMonth={(m) => setMonthFilter((p) => p === m ? null : m)}
            />
          </div>
        )}

        {/* Cash transactions */}
        {account.cash_transaction_count > 0 && (
          <div>
            <ChartLabel>Cash Transactions</ChartLabel>
            <Card>
              <CardContent className="p-0">
                <TransactionTable
                  transactions={transactions}
                  isLoading={txLoading}
                  columns={["date", "description", "merchant", "category", "amount"]}
                  resetKey={`${id}-${monthFilter}`}
                  exportScope={{ account_id: id }}
                  initialFilters={monthFilter ? [{ _key: 1, field: "transaction_date", operator: "month", value: monthFilter }] : []}
                />
              </CardContent>
            </Card>
          </div>
        )}

        {/* Current holdings */}
        {account.portfolio_value > 0 && (
          <div>
            <ChartLabel>
              Holdings
              {holdingsData?.as_of_date && (
                <span className="ml-2 text-muted-foreground font-normal">as of {formatDate(holdingsData.as_of_date)}</span>
              )}
            </ChartLabel>
            <HoldingsTable
              exportDataset="holdings"
              exportScope={{ account_id: id }}
              isLoading={holdingsLoading}
              holdings={(holdingsData?.positions ?? []).map((p): HoldingRow => ({
                id:                p.id,
                security_id:       p.security_id,
                ticker:            p.security_ticker,
                name:              p.security_name,
                cusip:             p.security_cusip,
                label:             p.security_label,
                quantity:          p.quantity,
                price:             p.price,
                market_value:      p.market_value,
                cost_basis:        p.cost_basis,
                unrealized_gl:     p.unrealized_gl,
                unrealized_gl_pct: p.unrealized_gl_pct,
                asset_class:       p.asset_class,
                est_annual_income: p.est_annual_income,
                dividend_yield:    p.dividend_yield,
                as_of_date:        p.as_of_date,
              }))}
            />
          </div>
        )}

        {/* Investment transactions */}
        {account.investment_transaction_count > 0 && (
          <div>
            <ChartLabel>Investment Transactions</ChartLabel>
            <InvestmentTransactionTable
              transactions={investmentTxns}
              isLoading={invLoading}
              showSecurity
            />
          </div>
        )}

        {account.cash_transaction_count === 0 && account.investment_transaction_count === 0 && (
          <EmptyState
            title="No transactions yet."
            description="Import a CSV or sync from Plaid to record activity for this account."
          />
        )}
      </div>
    </div>
  );
}

// ── AccountEditForm ───────────────────────────────────────────────────────────

const ACCOUNT_TYPES = ["checking", "savings", "credit card", "brokerage", "ira", "401k", "mortgage", "loan", "auto loan", "line of credit", "other"];

function AccountEditForm({ account, saving, onSave, onCancel }: {
  account: Account;
  saving: boolean;
  onSave: (patch: { name: string; account_number: string; account_type: string; balance: number | null; hidden: boolean; tax_treatment: string }) => void;
  onCancel: () => void;
}) {
  const [name, setName]       = useState(account.name);
  const [number, setNumber]   = useState(account.account_number ?? "");
  const [type, setType]       = useState(account.account_type ?? "");
  const [balance, setBalance] = useState(account.balance != null ? String(account.balance) : "");
  const [hidden, setHidden]   = useState(account.hidden);
  const [taxTreatment, setTaxTreatment] = useState(account.tax_treatment ?? "taxable");

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const parsedBalance = balance.trim() === "" ? null : parseFloat(balance);
    onSave({ name: name.trim(), account_number: number.trim(), account_type: type.trim(), balance: parsedBalance, hidden, tax_treatment: taxTreatment });
  }

  return (
    <form onSubmit={handleSubmit} className="border-b bg-muted/30 px-6 py-4 space-y-3">
      <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Edit Account</p>
      <div className="grid grid-cols-4 gap-3">
        <Field label="Name" htmlFor="account-edit-name">
          <Input
            id="account-edit-name"
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </Field>
        <Field label="Account number" htmlFor="account-edit-number">
          <Input
            id="account-edit-number"
            value={number}
            onChange={(e) => setNumber(e.target.value)}
            placeholder="Optional"
          />
        </Field>
        <Field label="Type" htmlFor="account-edit-type">
          <Input
            id="account-edit-type"
            list="account-type-options"
            value={type}
            onChange={(e) => setType(e.target.value)}
            placeholder="e.g. checking"
          />
          <datalist id="account-type-options">
            {ACCOUNT_TYPES.map((t) => <option key={t} value={t} />)}
          </datalist>
        </Field>
        <Field label="Balance" htmlFor="account-edit-balance">
          <Input
            id="account-edit-balance"
            type="number"
            step="0.01"
            value={balance}
            onChange={(e) => setBalance(e.target.value)}
            placeholder="Optional"
            className="tabular-nums [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
          />
        </Field>
      </div>
      <div className="flex flex-wrap items-end gap-4">
        <Field label="Tax treatment" htmlFor="account-edit-tax-treatment" className="w-56">
          <Select
            id="account-edit-tax-treatment"
            value={taxTreatment}
            onChange={(e) => setTaxTreatment(e.target.value as Account["tax_treatment"])}
          >
            <option value="taxable">Taxable</option>
            <option value="traditional_401k">Traditional 401(k)</option>
            <option value="roth_401k">Roth 401(k)</option>
            <option value="traditional_ira">Traditional IRA</option>
            <option value="roth_ira">Roth IRA</option>
            <option value="hsa">HSA</option>
            <option value="education">529 / education</option>
            <option value="other">Other</option>
          </Select>
        </Field>
        <label className="flex items-center gap-2 cursor-pointer select-none pb-2">
          <Checkbox
            checked={hidden}
            onChange={(e) => setHidden(e.target.checked)}
          />
          <span className="text-xs text-muted-foreground">Hide from household</span>
        </label>
      </div>
      <div className="flex items-center gap-2">
        <Button type="button" variant="ghost" size="sm" onClick={onCancel}
          className="text-muted-foreground hover:text-foreground">
          Cancel
        </Button>
        <Button type="submit" size="sm" disabled={saving || !name.trim()}>
          {saving ? "Saving…" : "Save changes"}
        </Button>
      </div>
    </form>
  );
}
