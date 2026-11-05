import { cn } from "@/lib/utils";
import { Label } from "@/components/ui/label";

// ── Form field scaffolding ────────────────────────────────────────────────────
// Standard vertical field: label (with required marker), control, error line.
//
//   <Field label="Name" required error={errors.name} htmlFor="name">
//     <Input id="name" … />
//   </Field>

export function Field({ label, required, error, htmlFor, className, children }: {
  label?: string;
  required?: boolean;
  error?: string | null;
  htmlFor?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={cn("space-y-1", className)}>
      {label && (
        <Label htmlFor={htmlFor} required={required}>
          {label}
        </Label>
      )}
      {children}
      <FieldError>{error}</FieldError>
    </div>
  );
}

/** The app's one way to render a field-level validation error. */
export function FieldError({ children, className }: { children?: React.ReactNode; className?: string }) {
  if (!children) return null;
  return (
    <p role="alert" className={cn("text-xs text-destructive", className)}>
      {children}
    </p>
  );
}
