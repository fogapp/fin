import { createContext, useCallback, useContext, useRef, useState } from "react";
import { Dialog, DialogContent, DialogFooter } from "@/components/ui/dialog";
import * as RadixDialog from "@radix-ui/react-dialog";
import { Button } from "@/components/ui/button";

// ── Confirm dialog ────────────────────────────────────────────────────────────
// Promise-based replacement for window.confirm, themed and keyboard-accessible:
//
//   const confirm = useConfirm();
//   if (await confirm({ title: `Delete "${name}"?`, destructive: true })) mutate();
//
// ConfirmProvider is mounted once in App.tsx.

export interface ConfirmOptions {
  title: string;
  description?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  /** Styles the confirm button as destructive (delete/remove actions). */
  destructive?: boolean;
}

type ConfirmFn = (opts: ConfirmOptions) => Promise<boolean>;

const ConfirmContext = createContext<ConfirmFn | null>(null);

export function useConfirm(): ConfirmFn {
  const fn = useContext(ConfirmContext);
  if (!fn) throw new Error("useConfirm must be used within <ConfirmProvider>");
  return fn;
}

export function ConfirmProvider({ children }: { children: React.ReactNode }) {
  const [opts, setOpts] = useState<ConfirmOptions | null>(null);
  const resolver = useRef<(v: boolean) => void>(null);

  const confirm = useCallback<ConfirmFn>((options) => {
    return new Promise<boolean>((resolve) => {
      resolver.current?.(false);
      resolver.current = resolve;
      setOpts(options);
    });
  }, []);

  const settle = (value: boolean) => {
    resolver.current?.(value);
    resolver.current = null;
    setOpts(null);
  };

  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      <Dialog open={opts !== null} onOpenChange={(open) => { if (!open) settle(false); }}>
        {opts && (
          <DialogContent size="sm" role="alertdialog">
            <div className="space-y-1 px-5 py-4">
              <RadixDialog.Title asChild>
                <h2 className="font-semibold">{opts.title}</h2>
              </RadixDialog.Title>
              {opts.description && <p className="text-sm text-muted-foreground">{opts.description}</p>}
            </div>
            <DialogFooter>
              <Button variant="outline" size="sm" onClick={() => settle(false)}>
                {opts.cancelLabel ?? "Cancel"}
              </Button>
              <Button
                variant={opts.destructive ? "destructive" : "default"}
                size="sm"
                autoFocus
                onClick={() => settle(true)}
              >
                {opts.confirmLabel ?? "Confirm"}
              </Button>
            </DialogFooter>
          </DialogContent>
        )}
      </Dialog>
    </ConfirmContext.Provider>
  );
}
