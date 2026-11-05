import { lazy } from "react";
import { BrowserRouter, Routes, Route, Navigate, useLocation } from "react-router-dom";
import { QueryClientProvider } from "@tanstack/react-query";
import { AuthProvider } from "@/hooks/AuthProvider";
import { useAuth } from "@/hooks/useAuth";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { createAppQueryClient } from "@/lib/queryClient";
import { Toaster } from "@/components/ui/toast";
import { ConfirmProvider } from "@/components/ui/confirm";
import { AppShell } from "@/components/layout/AppShell";
// Auth flow pages stay eager — they must paint instantly and pull none of
// the heavy chart/page code.
import { Landing } from "@/pages/Landing";
import { Login } from "@/pages/Login";
import { Register } from "@/pages/Register";
import { JoinDevice } from "@/pages/JoinDevice";
import { SigninComplete, SigninLink } from "@/pages/SigninHandoff";
import { ConnectApp, ConnectAppSignin } from "@/pages/ConnectApp";

// Every app page is route-split so the initial bundle carries no page code
// (and none of Recharts/dnd-kit/Plaid). AppShell renders the Suspense
// boundary around its Outlet.
const Dashboard         = lazy(() => import("@/pages/Dashboard").then((m) => ({ default: m.Dashboard })));
const Settings          = lazy(() => import("@/pages/Settings").then((m) => ({ default: m.Settings })));
const Categories        = lazy(() => import("@/pages/Categories").then((m) => ({ default: m.Categories })));
const Transactions      = lazy(() => import("@/pages/Transactions").then((m) => ({ default: m.Transactions })));
const TransactionDetail = lazy(() => import("@/pages/TransactionDetail").then((m) => ({ default: m.TransactionDetail })));
const Merchants         = lazy(() => import("@/pages/Merchants").then((m) => ({ default: m.Merchants })));
const Accounts          = lazy(() => import("@/pages/Accounts").then((m) => ({ default: m.Accounts })));
const Cashflow          = lazy(() => import("@/pages/Cashflow").then((m) => ({ default: m.Cashflow })));
const Investments       = lazy(() => import("@/pages/Investments").then((m) => ({ default: m.Investments })));
const Taxes             = lazy(() => import("@/pages/Taxes").then((m) => ({ default: m.Taxes })));
const Market            = lazy(() => import("@/pages/Market").then((m) => ({ default: m.Market })));
const SecurityDetail    = lazy(() => import("@/pages/SecurityDetail").then((m) => ({ default: m.SecurityDetail })));
const StatsIndex        = lazy(() => import("@/pages/stats/StatsIndex").then((m) => ({ default: m.StatsIndex })));
const StatDetail        = lazy(() => import("@/pages/stats/StatDetail").then((m) => ({ default: m.StatDetail })));
const Tags              = lazy(() => import("@/pages/Tags").then((m) => ({ default: m.Tags })));
const WorkflowsIndex    = lazy(() => import("@/pages/workflows/WorkflowsIndex").then((m) => ({ default: m.WorkflowsIndex })));
const WorkflowEditor    = lazy(() => import("@/pages/workflows/WorkflowEditor").then((m) => ({ default: m.WorkflowEditor })));
const WorkflowRunsPage  = lazy(() => import("@/pages/workflows/WorkflowRunsPage").then((m) => ({ default: m.WorkflowRunsPage })));
const Activity          = lazy(() => import("@/pages/Activity").then((m) => ({ default: m.Activity })));
const MonthlyReview     = lazy(() => import("@/pages/MonthlyReview").then((m) => ({ default: m.MonthlyReview })));
const Loans             = lazy(() => import("@/pages/Loans").then((m) => ({ default: m.Loans })));
const LoanDetail        = lazy(() => import("@/pages/LoanDetail").then((m) => ({ default: m.LoanDetail })));

const queryClient = createAppQueryClient();

// Redirect for pages that became rail sections (e.g. /budget →
// /cashflow#section=budget), preserving any other hash params (like #month=…).
function SectionRedirect({ to, section }: { to: string; section: string }) {
  const location = useLocation();
  const params = new URLSearchParams(location.hash.slice(1));
  params.set("section", section);
  return <Navigate to={{ pathname: to, hash: params.toString() }} replace />;
}

export default function App() {
  return (
    <ErrorBoundary>
      <AuthProvider>
        <QueryClientProvider client={queryClient}>
          <ConfirmProvider>
            <BrowserRouter>
              <AppRoutes />
            </BrowserRouter>
            <Toaster />
          </ConfirmProvider>
        </QueryClientProvider>
      </AuthProvider>
    </ErrorBoundary>
  );
}

export function AppRoutes() {
  const { isAuthenticated, login } = useAuth();

  if (isAuthenticated) {
    return (
      <Routes>
        <Route path="join-device" element={<JoinDevice onLogin={login} />} />
        {/* A fog sign-in or recovery link replaces whatever session this
            browser held. */}
        <Route path="auth/complete" element={<SigninComplete />} />
        <Route path="auth/link"     element={<SigninLink />} />
        {/* fog's consent page: a household admin lets an app read Fin. */}
        <Route path="connect/:ticket" element={<ConnectApp />} />
        <Route element={<AppShell />}>
          <Route index element={<Dashboard />} />
          <Route path="net-worth" element={<SectionRedirect to="/investments" section="net_worth" />} />
          <Route path="transactions" element={<Transactions />} />
          <Route path="transactions/:id" element={<TransactionDetail />} />
          <Route path="cashflow" element={<Cashflow />} />
          <Route path="budget" element={<SectionRedirect to="/cashflow" section="budget" />} />
          <Route path="subscriptions" element={<SectionRedirect to="/cashflow" section="subscriptions" />} />
          <Route path="investments" element={<Investments />} />
          <Route path="equity" element={<SectionRedirect to="/investments" section="equity" />} />
          <Route path="taxes" element={<Taxes />} />
          <Route path="market" element={<Market />} />
          <Route path="market/:id" element={<SecurityDetail />} />
          <Route path="review" element={<MonthlyReview />} />
          <Route path="stats" element={<StatsIndex />} />
          <Route path="stats/:key" element={<StatDetail />} />
          <Route path="accounts" element={<Accounts />} />
          <Route path="loans" element={<Loans />} />
          <Route path="loans/:id" element={<LoanDetail />} />
          <Route path="merchants" element={<Merchants />} />
          <Route path="categories" element={<Categories />} />
          <Route path="tags" element={<Tags />} />
          <Route path="workflows" element={<WorkflowsIndex />} />
          <Route path="workflows/new" element={<WorkflowEditor />} />
          <Route path="workflows/:id" element={<WorkflowEditor />} />
          <Route path="workflows/:id/runs" element={<WorkflowRunsPage />} />
          <Route path="activity" element={<Activity />} />
          <Route path="settings" element={<Settings />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    );
  }

  return (
    <Routes>
      <Route index element={<Landing />} />
      <Route path="login"       element={<Login     onLogin={login} />} />
      <Route path="register"    element={<Register  onLogin={login} />} />
      <Route path="join-device" element={<JoinDevice onLogin={login} />} />
      {/* Sign in with fog: the callback's handoff, and the link page. */}
      <Route path="auth/complete" element={<SigninComplete />} />
      <Route path="auth/link"     element={<SigninLink />} />
      <Route path="connect/:ticket" element={<ConnectAppSignin />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
