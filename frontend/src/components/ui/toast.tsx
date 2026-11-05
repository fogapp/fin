import { useEffect, useState } from "react";
import { AlertCircle, Check, Info } from "lucide-react";

// ── Toast ─────────────────────────────────────────────────────────────────────
// App-wide transient notifications. Call `toast.success("Saved")` /
// `toast.error(...)` / `toast.info(...)` from anywhere (components, mutation
// callbacks, the global MutationCache handler). One <Toaster/> is mounted in
// App.tsx; do not hand-roll per-page toasts. Pass `{ action }` for a follow-up
// button (the Toaster sits outside the router, so actions take a callback, not a Link).

type ToastKind = "success" | "error" | "info";
interface ToastAction {
  label: string;
  onClick: () => void;
}
interface ToastOptions {
  action?: ToastAction;
}
interface ToastItem extends ToastOptions {
  id: number;
  kind: ToastKind;
  message: string;
}

type Listener = (t: ToastItem) => void;
let listeners: Listener[] = [];
let nextId = 1;

function push(kind: ToastKind, message: string, options: ToastOptions = {}) {
  const item = { id: nextId++, kind, message, ...options };
  listeners.forEach((l) => l(item));
}

export const toast = {
  success: (message: string, options?: ToastOptions) => push("success", message, options),
  error: (message: string, options?: ToastOptions) => push("error", message, options),
  info: (message: string, options?: ToastOptions) => push("info", message, options),
};

const ICONS: Record<ToastKind, React.ReactNode> = {
  success: <Check size={14} className="shrink-0 text-positive" />,
  error: <AlertCircle size={14} className="shrink-0 text-destructive" />,
  info: <Info size={14} className="shrink-0 text-primary" />,
};

const TOAST_DURATION_MS = 4000;
/** Actionable toasts linger a little longer so there's time to reach the button. */
const ACTION_TOAST_DURATION_MS = 6000;

export function Toaster() {
  const [items, setItems] = useState<ToastItem[]>([]);

  const dismiss = (id: number) => setItems((prev) => prev.filter((x) => x.id !== id));

  useEffect(() => {
    const listener: Listener = (t) => {
      setItems((prev) => [...prev, t]);
      setTimeout(() => dismiss(t.id), t.action ? ACTION_TOAST_DURATION_MS : TOAST_DURATION_MS);
    };
    listeners.push(listener);
    return () => {
      listeners = listeners.filter((l) => l !== listener);
    };
  }, []);

  if (items.length === 0) return null;
  return (
    <div className="pointer-events-none fixed bottom-4 right-4 z-[60] flex flex-col items-end gap-2">
      {items.map((t) => (
        <div
          key={t.id}
          role="status"
          className="pointer-events-auto flex items-center gap-2 rounded-lg border bg-card px-3 py-2 text-sm text-card-foreground shadow-lg"
          style={{ animation: "toast-in 0.18s ease-out" }}
        >
          {ICONS[t.kind]}
          {t.message}
          {t.action && (
            <button
              type="button"
              onClick={() => { t.action!.onClick(); dismiss(t.id); }}
              className="ml-1 shrink-0 rounded font-medium text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              {t.action.label}
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
