import { useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/client";
import { invalidate, keys } from "@/api/keys";
import type { SecurityConversion } from "@/api/types";

/**
 * Confirm, dismiss or delete a security conversion. Each one changes how the
 * portfolio's history is valued, so besides the conversion list and the
 * issue it answers, the valuation pages refresh too.
 */
export function useSecurityConversionActions() {
  const qc = useQueryClient();
  const refresh = () =>
    invalidate(qc, keys.securityConversions, keys.issues, keys.portfolio, keys.netWorth, keys.dashboard, keys.stats);

  const confirm = useMutation({
    mutationFn: (id: string) => api.post<SecurityConversion>(`/security_conversions/${id}/confirm`, {}),
    onSuccess: refresh,
  });

  const dismiss = useMutation({
    mutationFn: (id: string) => api.post<SecurityConversion>(`/security_conversions/${id}/dismiss`, {}),
    onSuccess: refresh,
  });

  const remove = useMutation({
    mutationFn: (id: string) => api.delete(`/security_conversions/${id}`),
    onSuccess: refresh,
  });

  return { confirm, dismiss, remove };
}

/** The conversion an issue is about, when it's a conversion suggestion. */
export function conversionIdFromIssueKey(key: string | null | undefined): string | null {
  const prefix = "security_conversion:";
  return key?.startsWith(prefix) ? key.slice(prefix.length) : null;
}
