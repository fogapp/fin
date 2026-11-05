import { AlertCircle, CheckCircle } from "lucide-react";
import { cn } from "@/lib/utils";
import type { TestResult } from "./useTestConnection";

/** The outcome of an integration's "Test connection", or nothing before one runs. */
export function TestResultBanner({ result }: { result: TestResult | null }) {
  if (!result) return null;
  return (
    <div className={cn(
      "mt-3 flex items-center gap-2 rounded-md px-3 py-2 text-sm",
      result.ok ? "bg-positive/10 text-positive" : "bg-destructive/10 text-destructive",
    )}>
      {result.ok ? <CheckCircle size={14} /> : <AlertCircle size={14} />}
      {result.ok ? result.message : result.error}
    </div>
  );
}
