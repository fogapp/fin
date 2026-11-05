import { describe, it, expect, vi } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

vi.mock("@/api/client", () => ({ api: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() } }));

import { api } from "@/api/client";
import { useLoanPatch } from "./useLoanPatch";

describe("useLoanPatch", () => {
  it("invalidates the loans list as well as the detail", async () => {
    vi.mocked(api.patch).mockResolvedValue({} as never);
    const client = new QueryClient({ defaultOptions: { mutations: { retry: false } } });
    const spy = vi.spyOn(client, "invalidateQueries");
    const onSuccess = vi.fn();
    const { result } = renderHook(() => useLoanPatch("loan-1", { onSuccess }), {
      wrapper: ({ children }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>,
    });

    act(() => result.current.mutate({ interest_only: true }));

    await waitFor(() => expect(onSuccess).toHaveBeenCalled());
    expect(api.patch).toHaveBeenCalledWith("/loans/loan-1", { interest_only: true });
    expect(spy).toHaveBeenCalledWith({ queryKey: ["loans"] });
  });
});
