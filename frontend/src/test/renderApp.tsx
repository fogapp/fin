import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { render, type RenderOptions } from "@testing-library/react";
import { AuthProvider } from "@/hooks/AuthProvider";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { ConfirmProvider } from "@/components/ui/confirm";
import { Toaster } from "@/components/ui/toast";
import { AppRoutes } from "@/App";
import { createAppQueryClient } from "@/lib/queryClient";
import { setToken, clearToken } from "@/api/client";

interface Options {
  /** Initial URL the MemoryRouter renders at (default: "/"). Pass an object
   *  to also seed router state (e.g. { pathname, state }). */
  initialPath?: string | { pathname: string; state?: unknown };
  /** Pre-seed localStorage with a token, simulating "already signed in". */
  initialToken?: string | null;
  /** Use App's production QueryCache/MutationCache wiring (incl. the 401
   *  global handler). Default is a stripped-down test client. */
  useAppClient?: boolean;
  /** RTL options forwarded to render(). */
  renderOptions?: RenderOptions;
}

/** Render <AppRoutes /> with the same providers as App.tsx, inside a
 *  MemoryRouter so tests can drive navigation. */
export function renderApp({ initialPath = "/", initialToken = null, useAppClient = false, renderOptions }: Options = {}) {
  if (initialToken) setToken(initialToken);
  else clearToken();

  const client = useAppClient
    ? createAppQueryClient()
    : new QueryClient({
        defaultOptions: {
          queries: { retry: false, gcTime: Infinity, staleTime: 0 },
          mutations: { retry: false },
        },
      });

  return {
    client,
    ...render(
      <ErrorBoundary>
        <AuthProvider>
          <QueryClientProvider client={client}>
            <ConfirmProvider>
              <MemoryRouter initialEntries={[ initialPath ]}>
                <AppRoutes />
              </MemoryRouter>
              <Toaster />
            </ConfirmProvider>
          </QueryClientProvider>
        </AuthProvider>
      </ErrorBoundary>,
      renderOptions,
    ),
  };
}
