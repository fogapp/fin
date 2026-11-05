import { Button } from "@/components/ui/button";

/** Full-page centered error message, e.g. `title="Failed to load dashboard"`.
 * Pass `onRetry` (usually the query's `refetch`) to offer a retry button. */
export function ErrorState({ title, message, onRetry }: {
  title: string;
  message?: string;
  onRetry?: () => void;
}) {
  return (
    <div className="flex h-full items-center justify-center p-12 text-center">
      <div className="space-y-2">
        <p className="font-medium text-destructive">{title}</p>
        {message && <p className="text-sm text-muted-foreground">{message}</p>}
        {onRetry && (
          <Button variant="outline" size="sm" onClick={onRetry}>
            Try again
          </Button>
        )}
      </div>
    </div>
  );
}

/** Small centered muted placeholder shown in place of a chart with no data. */
export function EmptyChart({ message }: { message: string }) {
  return (
    <div className="flex h-[140px] items-center justify-center text-xs text-muted-foreground">
      {message}
    </div>
  );
}
