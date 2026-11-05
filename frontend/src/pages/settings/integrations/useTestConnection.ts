import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { api } from "@/api/client";

export interface TestResult {
  ok: boolean;
  message?: string;
  error?: string;
}

/**
 * "Test connection" for an integration: POSTs `${configPath}/test` and keeps
 * the latest outcome (a request error reads as a failed test) for
 * <TestResultBanner>. `test()` clears the previous outcome first.
 */
export function useTestConnection(configPath: string, { onTested }: { onTested?: () => void } = {}) {
  const [result, setResult] = useState<TestResult | null>(null);
  const mutation = useMutation({
    mutationFn: () => api.post<TestResult>(`${configPath}/test`),
    onSuccess: (data) => {
      setResult(data);
      onTested?.();
    },
    onError: (e: Error) => setResult({ ok: false, error: e.message }),
  });
  return {
    result,
    isPending: mutation.isPending,
    test: () => {
      setResult(null);
      mutation.mutate();
    },
  };
}
