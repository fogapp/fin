import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Trash2 } from "lucide-react";
import { queries } from "@/api/queries";
import type { SecurityConversion } from "@/api/types";
import { ChartLabel } from "@/components/charts";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { useSecurityConversionActions } from "@/hooks/mutations/useSecurityConversionActions";
import { formatDate } from "@/lib/utils";

function label(security: SecurityConversion["from_security"]) {
  return security.ticker || security.name || "Unknown";
}

function formatRatio(ratio: number) {
  return Number.isInteger(ratio) ? String(ratio) : ratio.toFixed(4).replace(/0+$/, "");
}

/**
 * Confirmed conversions this security is part of (either side) — the reason
 * its valuation history hands off to, or picks up from, another instrument.
 * Hidden when there are none.
 */
export function SecurityConversionsCard({ securityId }: { securityId: string }) {
  const { data: conversions = [] } = useQuery(queries.securityConversions({ securityId, status: "confirmed" }));
  const { remove } = useSecurityConversionActions();
  const confirm = useConfirm();

  if (conversions.length === 0) return null;

  return (
    <div>
      <ChartLabel>Conversions</ChartLabel>
      <Card>
        <CardContent className="divide-y p-0">
          {conversions.map((c) => (
            <div key={c.id} className="flex items-center gap-3 px-4 py-2.5 text-sm">
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-1.5 font-medium">
                  {label(c.from_security)} <ArrowRight size={13} className="text-muted-foreground" /> {label(c.to_security)}
                </p>
                <p className="text-xs text-muted-foreground">
                  {formatRatio(c.ratio)} {label(c.to_security)} per {label(c.from_security)} share · effective{" "}
                  {formatDate(c.effective_date)}
                </p>
              </div>
              <Button
                variant="ghost"
                size="icon-sm"
                aria-label={`Remove conversion ${label(c.from_security)} to ${label(c.to_security)}`}
                disabled={remove.isPending}
                onClick={async () => {
                  const ok = await confirm({
                    title: "Remove this conversion?",
                    description: "Valuations will count the two instruments separately again.",
                    confirmLabel: "Remove",
                    destructive: true,
                  });
                  if (ok) remove.mutate(c.id);
                }}
              >
                <Trash2 size={14} />
              </Button>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
