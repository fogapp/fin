import * as RadixDialog from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

// ── Dialog ────────────────────────────────────────────────────────────────────
// The app's one modal implementation, built on Radix Dialog so every modal gets
// portal rendering, focus trap, scroll lock, Escape/overlay dismiss, and
// role="dialog"/aria-modal for free. Compose:
//
//   <Dialog open={open} onOpenChange={setOpen}>
//     <DialogContent size="md">
//       <DialogHeader title="Create thing" />
//       <div className="px-5 py-4">…body…</div>
//       <DialogFooter>
//         <Button variant="outline" onClick={close}>Cancel</Button>
//         <Button type="submit">Create thing</Button>   {/* Cancel left, primary right */}
//       </DialogFooter>
//     </DialogContent>
//   </Dialog>

export const Dialog = RadixDialog.Root;

interface DialogContentProps extends React.ComponentPropsWithoutRef<typeof RadixDialog.Content> {
  size?: "sm" | "md" | "lg";
}

export function DialogContent({ className, size = "md", children, ...props }: DialogContentProps) {
  return (
    <RadixDialog.Portal>
      <RadixDialog.Overlay className="fixed inset-0 z-40 bg-black/40" />
      <RadixDialog.Content
        aria-describedby={undefined}
        className={cn(
          "fixed left-1/2 top-1/2 z-50 max-h-[85vh] w-full -translate-x-1/2 -translate-y-1/2 overflow-y-auto rounded-xl border bg-card text-card-foreground shadow-xl focus:outline-none",
          { sm: "max-w-sm", md: "max-w-md", lg: "max-w-2xl" }[size],
          className,
        )}
        {...props}
      >
        {children}
      </RadixDialog.Content>
    </RadixDialog.Portal>
  );
}

/** Standard modal header: title on the left, close-X on the right. Extra
 * children render between them. */
export function DialogHeader({ title, className, children }: {
  title: string;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <div className={cn("flex items-center justify-between border-b px-5 py-4", className)}>
      <RadixDialog.Title asChild>
        <h2 className="font-semibold">{title}</h2>
      </RadixDialog.Title>
      {children}
      <RadixDialog.Close
        aria-label="Close"
        className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <X size={16} />
      </RadixDialog.Close>
    </div>
  );
}

/** Standard modal footer. Button order convention: Cancel on the left,
 * the primary action on the right. */
export function DialogFooter({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex items-center justify-end gap-2 border-t px-5 py-4", className)} {...props} />;
}
