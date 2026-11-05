import { forwardRef } from "react";

interface Props {
  value: string;
  onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onKeyDown: (e: React.KeyboardEvent<HTMLInputElement>) => void;
  placeholder?: string;
  /** Accessible name for the placeholder-only input (defaults to "Search"). */
  "aria-label"?: string;
}

export const SearchInput = forwardRef<HTMLInputElement, Props>(
  ({ value, onChange, onKeyDown, placeholder = "Search…", "aria-label": ariaLabel = "Search" }, ref) => (
    <input
      ref={ref}
      value={value}
      onChange={onChange}
      onKeyDown={onKeyDown}
      placeholder={placeholder}
      aria-label={ariaLabel}
      className="h-8 w-full bg-transparent px-3 text-sm placeholder:text-muted-foreground focus:outline-none"
    />
  )
);
SearchInput.displayName = "SearchInput";
