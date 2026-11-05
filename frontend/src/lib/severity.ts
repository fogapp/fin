import type { ActivitySeverity } from "@/api/types";

/**
 * The backend shares one Severity vocabulary across activity, issues and
 * notifications (info < warning < error < critical). Notifications have
 * historically used "critical" where the activity feed uses "error"; both are
 * the red tier, so UI that highlights failures should treat them alike.
 */
export function isSevere(severity: ActivitySeverity): boolean {
  return severity === "error" || severity === "critical";
}
