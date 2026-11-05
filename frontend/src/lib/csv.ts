import type { CashTransaction } from "@/api/types";

// RFC-4180 quoting: always quote, double any embedded quotes. Excel and
// Numbers both accept this unconditionally, which beats deciding per-value.
function cell(value: string | number | null | undefined): string {
  const s = value == null ? "" : String(value);
  return `"${s.replaceAll('"', '""')}"`;
}

const HEADER = [
  "Date", "Post date", "Description", "Merchant", "Category", "Account",
  "Amount", "Type", "Source", "Tags", "Memo",
];

/** The table's rows, in the table's order, as a CSV string. */
export function buildTransactionsCsv(rows: CashTransaction[]): string {
  const lines = [HEADER.map(cell).join(",")];
  for (const t of rows) {
    lines.push([
      cell(t.transaction_date),
      cell(t.post_date),
      cell(t.description),
      cell(t.merchant_name),
      cell(t.category_name),
      cell(t.account_name),
      cell(t.amount),
      cell(t.transaction_type),
      cell(t.source),
      cell((t.tags ?? []).map((tag) => tag.name).join("; ")),
      cell(t.memo),
    ].join(","));
  }
  return lines.join("\n");
}

/** Trigger a browser download of `content` as `filename`. */
export function downloadCsv(filename: string, content: string): void {
  const blob = new Blob([content], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
