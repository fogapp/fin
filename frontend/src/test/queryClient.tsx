import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render as rtlRender, type RenderOptions } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import type { ReactElement } from "react";
import { ConfirmProvider } from "@/components/ui/confirm";
import { Toaster } from "@/components/ui/toast";

/** Render with a fresh QueryClient, retries disabled. */
export function renderWithClient(ui: ReactElement, options?: RenderOptions) {
  const client = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: Infinity, staleTime: Infinity },
      mutations: { retry: false },
    },
  });
  return {
    client,
    ...rtlRender(
      <QueryClientProvider client={client}>
        <ConfirmProvider>
          {ui}
          <Toaster />
        </ConfirmProvider>
      </QueryClientProvider>,
      options,
    ),
  };
}

/** Render with both a QueryClient and a MemoryRouter. */
export function renderWithRouter(ui: ReactElement, options?: RenderOptions) {
  const client = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: Infinity, staleTime: Infinity },
      mutations: { retry: false },
    },
  });
  return {
    client,
    ...rtlRender(
      <QueryClientProvider client={client}>
        <ConfirmProvider>
          <MemoryRouter>{ui}</MemoryRouter>
          <Toaster />
        </ConfirmProvider>
      </QueryClientProvider>,
      options,
    ),
  };
}
