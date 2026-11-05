/**
 * Picker for the dashboard's insight widgets: reorder/remove what's shown,
 * add anything from the full registry, or reset to the defaults. Clicking a
 * row renders that widget live in a preview pane so its contents can be seen
 * before adding it. Selection is local until Save.
 */
import { useState } from "react";
import { GripVertical } from "lucide-react";
import {
  DndContext, KeyboardSensor, PointerSensor, closestCenter, useSensor, useSensors, type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext, arrayMove, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { Dialog, DialogContent, DialogFooter, DialogHeader } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { cn } from "@/lib/utils";
import { WIDGET_CATEGORIES, WIDGET_MAP, WIDGETS, type WidgetDef } from "./registry";

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  selected: string[];
  /** Persist a new selection; `null` resets to defaults. */
  onSave: (ids: string[] | null) => void;
}

export function CustomizeDialog({ open, onOpenChange, selected, onSave }: Props) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      {/* Radix unmounts the content on close, so mounting here re-seeds the
          draft selection from `selected` every time the dialog opens. */}
      <DialogBody onOpenChange={onOpenChange} selected={selected} onSave={onSave} />
    </Dialog>
  );
}

function DialogBody({ onOpenChange, selected, onSave }: Omit<Props, "open">) {
  const [ids, setIds] = useState<string[]>(selected);
  const [previewId, setPreviewId] = useState<string | null>(null);
  const preview = previewId ? WIDGET_MAP.get(previewId) : undefined;

  const remove = (id: string) => setIds((cur) => cur.filter((x) => x !== id));
  const add = (id: string) => setIds((cur) => [...cur, id]);

  const sensors = useSensors(
    // A small activation distance keeps plain clicks on the row's checkbox
    // and text from starting a drag.
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  const onDragEnd = ({ active, over }: DragEndEvent) => {
    if (over && active.id !== over.id) {
      setIds((cur) => arrayMove(cur, cur.indexOf(String(active.id)), cur.indexOf(String(over.id))));
    }
  };

  const available = WIDGET_CATEGORIES
    .map((cat) => ({ cat, widgets: WIDGETS.filter((w) => w.category === cat && !ids.includes(w.id)) }))
    .filter((g) => g.widgets.length > 0);

  return (
    <DialogContent size="lg" className="sm:max-w-3xl">
      <DialogHeader title="Customize insights" />
      <div className="sm:flex">
        <div className="min-w-0 flex-1 space-y-5 px-5 py-4">
          <section>
            <p className="mb-2 text-xs font-medium text-muted-foreground">Shown, in order</p>
            {ids.length === 0 && (
              <p className="text-sm text-muted-foreground">Nothing selected — pick insights below.</p>
            )}
            <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
              <SortableContext items={ids} strategy={verticalListSortingStrategy}>
                <ul className="space-y-1">
                  {ids.map((id) => {
                    const w = WIDGET_MAP.get(id);
                    if (!w) return null;
                    return (
                      <SortableRow
                        key={id}
                        widget={w}
                        onRemove={() => remove(id)}
                        isPreviewed={previewId === id}
                        onPreview={() => setPreviewId(id)}
                      />
                    );
                  })}
                </ul>
              </SortableContext>
            </DndContext>
          </section>

          {available.map(({ cat, widgets }) => (
            <section key={cat}>
              <p className="mb-2 text-xs font-medium text-muted-foreground">{cat}</p>
              <ul className="space-y-1">
                {widgets.map((w) => (
                  <li
                    key={w.id}
                    className={cn(
                      "flex items-center gap-2 rounded-lg px-1.5 py-1 hover:bg-accent",
                      previewId === w.id && "bg-accent",
                    )}
                  >
                    <Checkbox checked={false} onChange={() => add(w.id)} aria-label={w.title} />
                    <RowLabel widget={w} onPreview={() => setPreviewId(w.id)} />
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
        {/* Live preview of the clicked row — sticky so it stays put while the
            list scrolls. Hidden on phones, where the panes would cram. */}
        <aside className="sticky top-0 hidden w-72 shrink-0 self-start border-l px-4 py-4 sm:block">
          <p className="mb-3 text-xs font-medium text-muted-foreground">Preview</p>
          {preview ? (
            <div key={preview.id}>
              <preview.Component showEmpty />
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">
              Select an insight to see a live preview of it here.
            </p>
          )}
        </aside>
      </div>
      <DialogFooter>
          <Button
            variant="ghost"
            onClick={() => { onSave(null); onOpenChange(false); }}
          >
            Reset to defaults
          </Button>
          <div className="flex-1" />
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={() => { onSave(ids); onOpenChange(false); }}>Save</Button>
      </DialogFooter>
    </DialogContent>
  );
}

function SortableRow({ widget, onRemove, isPreviewed, onPreview }: {
  widget: WidgetDef;
  onRemove: () => void;
  isPreviewed: boolean;
  onPreview: () => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: widget.id });

  return (
    <li
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition }}
      className={cn(
        "flex items-center gap-2 rounded-lg px-1.5 py-1 hover:bg-accent",
        isPreviewed && "bg-accent",
        isDragging && "relative z-10 bg-accent shadow-sm",
      )}
    >
      <button
        type="button"
        {...attributes}
        {...listeners}
        aria-label={`Reorder ${widget.title}`}
        className="cursor-grab touch-none rounded p-1 text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary active:cursor-grabbing"
      >
        <GripVertical size={14} />
      </button>
      <Checkbox checked onChange={onRemove} aria-label={widget.title} />
      <RowLabel widget={widget} onPreview={onPreview} />
    </li>
  );
}

/** The row's title/description block — clicking it previews the widget. */
function RowLabel({ widget, onPreview }: { widget: WidgetDef; onPreview: () => void }) {
  return (
    <button
      type="button"
      onClick={onPreview}
      className="min-w-0 flex-1 rounded text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <p className="truncate text-sm font-medium">{widget.title}</p>
      <p className="truncate text-xs text-muted-foreground">{widget.description}</p>
    </button>
  );
}
