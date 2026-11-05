import type { ReactNode } from "react";
import { Dialog, DialogContent, DialogHeader, DialogFooter } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { FieldError } from "@/components/ui/field";

// ── Form dialog ───────────────────────────────────────────────────────────────
// The standard create/edit dialog shell: header, a submit-guarded form around
// the caller's fields, an error slot, and the Cancel/submit footer with a
// pending label. Callers keep their own field state and mutation; this only
// owns the wiring every such dialog repeated.

export function FormDialog({
  title,
  size = "sm",
  onClose,
  onSubmit,
  canSubmit,
  isPending,
  error,
  submitLabel,
  pendingLabel = "Saving…",
  children,
}: {
  title: string;
  size?: "sm" | "md" | "lg";
  onClose: () => void;
  onSubmit: () => void;
  /** Gates both the footer button and Enter-key form submission. */
  canSubmit: boolean;
  isPending: boolean;
  error: string;
  submitLabel: string;
  pendingLabel?: string;
  children: ReactNode;
}) {
  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent size={size}>
        <DialogHeader title={title} />
        <form
          onSubmit={(e) => { e.preventDefault(); if (canSubmit) onSubmit(); }}
          className="space-y-4 p-5"
        >
          {children}
          <FieldError>{error}</FieldError>
        </form>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={isPending}>Cancel</Button>
          <Button onClick={onSubmit} disabled={!canSubmit}>
            {isPending ? pendingLabel : submitLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
