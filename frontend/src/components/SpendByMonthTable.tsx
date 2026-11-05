import { Card, CardContent } from "@/components/ui/card";
import { formatCurrency } from "@/lib/utils";

interface Props {
  data: { month: string; amount: number }[];
  /** How many recent months to show (default 6) */
  limit?: number;
}

export function SpendByMonthTable({ data, limit = 6 }: Props) {
  const rows = [...data].reverse().slice(0, limit);

  return (
    <Card>
      <CardContent className="p-0">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-xs text-muted-foreground">
              <th className="px-4 py-2.5 text-left font-medium">Month</th>
              <th className="px-4 py-2.5 text-right font-medium">Spend</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {rows.map(({ month, amount }, i, arr) => {
              const year     = month.slice(0, 4);
              const prevYear = i > 0 ? arr[i - 1].month.slice(0, 4) : year;
              const label    = new Date(month + "-02").toLocaleDateString("en-US", { month: "short" });
              return (
                <>
                  {i > 0 && year !== prevYear && (
                    <tr key={`divider-${year}`}>
                      <td colSpan={2} className="px-4 py-2">
                        <div className="flex items-center gap-2">
                          <div className="h-px flex-1 bg-muted" />
                          <span className="text-xs text-muted-foreground">{year}</span>
                          <div className="h-px flex-1 bg-muted" />
                        </div>
                      </td>
                    </tr>
                  )}
                  <tr key={month}>
                    <td className="px-4 py-2.5 text-muted-foreground">{label}</td>
                    <td className="px-4 py-2.5 text-right tabular-nums">{formatCurrency(amount)}</td>
                  </tr>
                </>
              );
            })}
          </tbody>
        </table>
      </CardContent>
    </Card>
  );
}
