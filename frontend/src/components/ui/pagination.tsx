import type { ReactNode } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type PaginationProps =
  | {
      /** Client-paged rows: "101–200 of 1,234" with icon steppers. `page` is zero-based. */
      variant: "range";
      page: number;
      pageSize: number;
      total: number;
      onPageChange: (page: number) => void;
      className?: string;
    }
  | {
      /** Server-paged lists: Previous · "Page 2 of 5 · …" · Next. `page` is one-based. */
      variant: "simple";
      page: number;
      totalPages: number;
      /** Trailing text after "Page x of y", e.g. "120 groups". */
      summary?: ReactNode;
      size?: "xs" | "sm";
      onPageChange: (page: number) => void;
      className?: string;
    };

/** Page controls for a list; renders nothing when everything fits on one page. */
export function Pagination(props: PaginationProps) {
  if (props.variant === "range") {
    const { page, pageSize, total, onPageChange, className } = props;
    const totalPages = Math.ceil(total / pageSize);
    if (totalPages <= 1) return null;
    return (
      <div className={cn("flex items-center justify-between border-t px-4 py-2.5 text-xs text-muted-foreground", className)}>
        <span>
          {page * pageSize + 1}–{Math.min((page + 1) * pageSize, total)} of {total}
        </span>
        <div className="flex items-center gap-1">
          <Button variant="ghost" size="icon" onClick={() => onPageChange(page - 1)} disabled={page === 0} aria-label="Previous page">
            <ChevronLeft size={14} />
          </Button>
          <span className="px-1">{page + 1} / {totalPages}</span>
          <Button variant="ghost" size="icon" onClick={() => onPageChange(page + 1)} disabled={page >= totalPages - 1} aria-label="Next page">
            <ChevronRight size={14} />
          </Button>
        </div>
      </div>
    );
  }

  const { page, totalPages, summary, size = "sm", onPageChange, className } = props;
  if (totalPages <= 1) return null;
  return (
    <div className={cn("flex items-center justify-between text-sm text-muted-foreground", className)}>
      <Button variant="outline" size={size} disabled={page <= 1} onClick={() => onPageChange(page - 1)}>
        Previous
      </Button>
      <span className="text-xs">
        Page {page} of {totalPages}
        {summary != null && <> · {summary}</>}
      </span>
      <Button variant="outline" size={size} disabled={page >= totalPages} onClick={() => onPageChange(page + 1)}>
        Next
      </Button>
    </div>
  );
}
