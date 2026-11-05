import * as RadixDialog from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

// ── Drawer ────────────────────────────────────────────────────────────────────
// Right-side sheet built on Radix Dialog (portal, focus trap, scroll lock,
// Escape/overlay dismiss, dialog semantics). For overlay-style drawers — the
// in-flow split-view panel in TransactionTable is a different pattern and
// intentionally not this component.
//
//   <Drawer open={open} onOpenChange={setOpen}>
//     <DrawerContent>
//       <DrawerHeader title="Add transaction" />
//       <div className="flex-1 overflow-y-auto p-4">…body…</div>
//       <DrawerFooter>…actions…</DrawerFooter>
//     </DrawerContent>
//   </Drawer>

export const Drawer = RadixDialog.Root;

export function DrawerContent({ className, children, ...props }: React.ComponentPropsWithoutRef<typeof RadixDialog.Content>) {
  return (
    <RadixDialog.Portal>
      <RadixDialog.Overlay className="fixed inset-0 z-40 bg-black/40" />
      <RadixDialog.Content
        aria-describedby={undefined}
        className={cn(
          "fixed inset-y-0 right-0 z-50 flex w-full flex-col border-l bg-card text-card-foreground shadow-xl focus:outline-none sm:w-96",
          className,
        )}
        {...props}
      >
        {children}
      </RadixDialog.Content>
    </RadixDialog.Portal>
  );
}

export function DrawerHeader({ title, className, children }: {
  title: string;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <div className={cn("flex items-center justify-between border-b px-4 py-3", className)}>
      <RadixDialog.Title asChild>
        <h2 className="text-sm font-medium">{title}</h2>
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

export function DrawerFooter({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("border-t p-4", className)} {...props} />;
}
