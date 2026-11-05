import { Badge } from "@/components/ui/badge";
import type { TaxKind } from "@/api/types";

// The tax center's core honesty device: every section declares whether its
// numbers are computed from ledger data (fact), user bookkeeping (record), or
// model output (estimate). Estimates can never masquerade as filing numbers.

const LABELS: Record<TaxKind, string> = {
  fact: "From your data",
  record: "Your records",
  estimate: "Estimate",
};

export function KindBadge({ kind }: { kind: TaxKind }) {
  return (
    <Badge
      variant={kind === "fact" ? "success" : kind === "estimate" ? "default" : "outline"}
      className="shrink-0"
    >
      {LABELS[kind]}
    </Badge>
  );
}
