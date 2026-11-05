import * as RadixPopover from "@radix-ui/react-popover";
import { cn } from "@/lib/utils";

// Radix-based popover for panels that hold more than a list of actions (a
// form, a date range, a checklist). Escape, outside click, focus return and
// collision-aware placement come from Radix. Styled like DropdownMenuContent
// so menus and panels read as one family; use DropdownMenu when the panel is
// just a list of actions.

export const Popover = RadixPopover.Root;
export const PopoverTrigger = RadixPopover.Trigger;
export const PopoverAnchor = RadixPopover.Anchor;
export const PopoverClose = RadixPopover.Close;

export function PopoverContent({
  className,
  sideOffset = 4,
  align = "end",
  ...props
}: React.ComponentProps<typeof RadixPopover.Content>) {
  return (
    <RadixPopover.Portal>
      <RadixPopover.Content
        sideOffset={sideOffset}
        align={align}
        className={cn(
          "z-50 rounded-lg border bg-card p-3 text-card-foreground shadow-md outline-none",
          className,
        )}
        {...props}
      />
    </RadixPopover.Portal>
  );
}
