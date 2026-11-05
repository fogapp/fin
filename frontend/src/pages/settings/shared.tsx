import { cn } from "@/lib/utils";

export function SettingsToggle({ checked, onChange, label, description, indent }: {
  checked: boolean;
  onChange: () => void;
  label: string;
  description?: React.ReactNode;
  indent?: boolean;
}) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      onClick={onChange}
      className={cn(
        "flex items-center gap-3 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        indent && "ml-6",
      )}
    >
      <div className={cn(
        "relative h-5 w-9 shrink-0 rounded-full transition-colors",
        checked ? "bg-primary" : "bg-input",
      )}>
        <div className={cn(
          "absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition-transform",
          checked ? "translate-x-4" : "translate-x-0.5",
        )} />
      </div>
      <div>
        <p className="text-left text-sm font-medium">{label}</p>
        {description && (
          <p className="mt-0.5 text-left text-xs text-muted-foreground">{description}</p>
        )}
      </div>
    </button>
  );
}
