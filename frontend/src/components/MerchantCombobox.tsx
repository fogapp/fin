import { api } from "@/api/client";
import { EntityCombobox } from "@/components/EntityCombobox";
import type { Merchant, MerchantSummary } from "@/api/types";
import { keys } from "@/api/keys";

interface Props {
  value: string;
  onChange: (merchantId: string) => void;
  merchants: MerchantSummary[];
  placeholder?: string;
  className?: string;
  inputClassName?: string;
  autoFocus?: boolean;
  onClose?: () => void;
}

/** Search-or-create merchant picker; the interaction model lives in EntityCombobox. */
export function MerchantCombobox({ value, onChange, merchants, placeholder = "Search or create merchant…", className, inputClassName, autoFocus, onClose }: Props) {
  return (
    <EntityCombobox
      value={value}
      onChange={onChange}
      items={merchants}
      getId={(m) => m.id}
      getLabel={(m) => m.name}
      filter={(m, query) => m.name.toLowerCase().includes(query)}
      renderOption={(m) => m.name}
      ariaLabel="Merchant"
      placeholder={placeholder}
      className={className}
      inputClassName={inputClassName}
      autoFocus={autoFocus}
      onClose={onClose}
      create={{
        mutationFn: (name) => api.post<Merchant>("/merchants", { name }),
        invalidateKey: keys.merchants,
        label: (name) => <>Create &ldquo;{name}&rdquo;</>,
      }}
    />
  );
}
