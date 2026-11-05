import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ChevronRight, ChevronLeft } from "lucide-react";
import { queries } from "@/api/queries";
import { MerchantCombobox } from "@/components/MerchantCombobox";
import { AccountCombobox } from "@/components/AccountCombobox";
import { cn, formatMonthLabel } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Tabs } from "@/components/ui/tabs";
import type { ActiveFilter, FieldDef } from "./types";

// ── Shared picker content (field list + value sub-panel) ─────────────────────

const SUBMENU_WIDTH = 224;

export function PickerContent({ fields, hoveredField, setHoveredField, onCommit }: {
  fields: FieldDef[];
  hoveredField: FieldDef | null;
  setHoveredField: (f: FieldDef) => void;
  onCommit: (operator: string, value: string) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  // side is computed once when the dropdown mounts so all items open the same way
  const [side, setSide] = useState<"right" | "left">("right");
  const [submenuTop, setSubmenuTop] = useState(0);
  const [submenuAnchorX, setSubmenuAnchorX] = useState(0);

  useEffect(() => {
    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    if (window.innerWidth - rect.right >= SUBMENU_WIDTH) {
      setSide("right");
      setSubmenuAnchorX(rect.right - 3); // left edge of submenu (3px overlap)
    } else {
      setSide("left");
      setSubmenuAnchorX(rect.left - SUBMENU_WIDTH + 3); // left edge of submenu (3px overlap)
    }
  }, []);

  function handleRowEnter(f: FieldDef, e: { currentTarget: HTMLButtonElement }) {
    setHoveredField(f);
    setSubmenuTop(e.currentTarget.getBoundingClientRect().top);
  }

  return (
    <>
      <div ref={containerRef} className="min-w-40 py-1">
        {fields.map((f) => (
          <button
            key={f.key}
            onMouseEnter={(e) => handleRowEnter(f, e)}
            onFocus={(e) => handleRowEnter(f, e)}
            className={cn(
              "flex w-full items-center px-3 py-2 text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
              hoveredField?.key === f.key ? "bg-accent text-accent-foreground" : "hover:bg-accent"
            )}
          >
            {side === "left" && (
              <ChevronLeft size={13} className={cn("mr-1.5 shrink-0 text-muted-foreground", hoveredField?.key !== f.key && "opacity-0")} />
            )}
            <span className="flex-1 text-left">{f.label}</span>
            {side === "right" && (
              <ChevronRight size={13} className={cn("ml-1.5 shrink-0 text-muted-foreground", hoveredField?.key !== f.key && "opacity-0")} />
            )}
          </button>
        ))}
      </div>

      {/* Submenu — fixed so it escapes overflow-hidden on the parent Popover */}
      {hoveredField && submenuAnchorX > 0 && (
        <div
          style={{ position: "fixed", top: submenuTop, left: submenuAnchorX, zIndex: 9999, width: SUBMENU_WIDTH }}
          className="rounded-lg border bg-card shadow-xl overflow-hidden"
        >
          <AddFilterValueEditor key={hoveredField.key} field={hoveredField} onCommit={onCommit} />
        </div>
      )}
    </>
  );
}

// ── Add-filter value picker (step 2 — no table effect until commit) ───────────

function AddFilterValueEditor({ field, onCommit }: {
  field: FieldDef;
  onCommit: (operator: string, value: string) => void;
}) {
  const [op, setOp] = useState(field.defaultOperator);
  const [val, setVal] = useState("");
  const { data: merchants = [] } = useQuery({ ...queries.merchants(), enabled: field.editor.type === "merchant" });
  const { data: categories = [] } = useQuery({ ...queries.categories(), enabled: field.editor.type === "category" });
  const { data: accounts = [] } = useQuery({ ...queries.accounts(), enabled: field.editor.type === "account" });

  if (field.editor.type === "account") {
    return (
      <div className="min-w-56">
        <div className="p-2">
          <AccountCombobox
            value={val}
            onChange={(id) => { if (id) { setVal(id); onCommit(op, id); } }}
            accounts={accounts}
            allowCreate={false}
            placeholder="Search account…"
          />
        </div>
      </div>
    );
  }

  if (field.editor.type === "merchant") {
    return (
      <div className="min-w-56">
        <button
          onClick={() => onCommit("blank", "")}
          className="flex w-full items-center px-3 py-2 text-sm text-muted-foreground hover:bg-accent transition-colors border-b focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
        >
          No merchant
        </button>
        <div className="p-2">
          <MerchantCombobox
            value={val}
            onChange={(id) => { if (id) { setVal(id); onCommit(op, id); } }}
            merchants={merchants}
            placeholder="Search merchant…"
          />
        </div>
      </div>
    );
  }

  if (field.editor.type === "category") {
    return (
      <div className="min-w-48">
        <ul className="py-1">
          {categories.filter((c) => c.parent_id === null).map((c) => (
            <li key={c.id}>
              <button onClick={() => onCommit(op, c.id)}
                className="flex w-full px-3 py-2 text-sm hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary">
                {c.name}
              </button>
            </li>
          ))}
        </ul>
      </div>
    );
  }

  if (field.editor.type === "select") {
    return (
      <div className="min-w-40">
        <ul className="py-1">
          {field.editor.options.map(({ value, label }) => (
            <li key={value}>
              <button onClick={() => onCommit(op, value)}
                className="flex w-full px-3 py-2 text-sm hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary">
                {label}
              </button>
            </li>
          ))}
        </ul>
      </div>
    );
  }

  if (field.editor.type === "date") {
    return (
      <div className="min-w-52">
        <div className="space-y-2 p-3">
          <Tabs
            size="sm"
            value={op}
            onChange={(o) => setOp(o)}
            options={[
              { value: "month", label: "Month" },
              { value: "gte", label: "After" },
              { value: "lte", label: "Before" },
            ]}
          />
          <Input
            key={op === "month" ? "month" : "date"}
            autoFocus
            type={op === "month" ? "month" : "date"}
            value={val}
            onChange={(e) => setVal(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && val && onCommit(op, val)}
            aria-label={op === "month" ? "Month" : "Date"}
            className="h-8 px-2"
          />
          <Button size="sm" className="w-full" onClick={() => val && onCommit(op, val)} disabled={!val}>
            Apply
          </Button>
        </div>
      </div>
    );
  }

  if (field.editor.type === "amount") {
    return (
      <div className="min-w-48">
        <div className="space-y-2 p-3">
          <Tabs
            size="sm"
            value={op}
            onChange={(o) => setOp(o)}
            options={[
              { value: "greater_than", label: ">" },
              { value: "equals", label: "=" },
              { value: "less_than", label: "<" },
            ]}
          />
          <Input autoFocus type="number" value={val} onChange={(e) => setVal(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && val && onCommit(op, val)}
            placeholder="Amount…"
            aria-label="Amount"
            className="h-8 px-2 tabular-nums" />
          <Button size="sm" className="w-full" onClick={() => val && onCommit(op, val)} disabled={!val}>
            Apply
          </Button>
        </div>
      </div>
    );
  }

  // text (default)
  const placeholder = field.editor.type === "text" ? (field.editor.placeholder ?? "Enter text…") : "Enter text…";
  return (
    <div className="min-w-48">
      <div className="space-y-2 p-3">
        <Input autoFocus value={val} onChange={(e) => setVal(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && val && onCommit(op, val)}
          placeholder={placeholder}
          aria-label={field.label}
          className="h-8 px-2" />
        <Button size="sm" className="w-full" onClick={() => val && onCommit(op, val)} disabled={!val}>
          Apply
        </Button>
      </div>
    </div>
  );
}

// ── Value display (inside pill) ───────────────────────────────────────────────

export function FilterValueDisplay({ filter, fieldDef }: { filter: ActiveFilter; fieldDef: FieldDef | undefined }) {
  const editorType = fieldDef?.editor.type;
  const { data: merchants = [] } = useQuery({ ...queries.merchants(), enabled: editorType === "merchant" });
  const { data: categories = [] } = useQuery({ ...queries.categories(), enabled: editorType === "category" });
  const { data: accounts = [] } = useQuery({ ...queries.accounts(), enabled: editorType === "account" });

  if (filter.operator === "blank" || filter.operator === "present") {
    return <span className="rounded bg-muted px-1.5 py-0.5 font-medium text-muted-foreground">empty</span>;
  }
  if (!filter.value) return null;

  let display = filter.value;

  if (editorType === "merchant") {
    display = merchants.find((m) => m.id === filter.value)?.name ?? filter.value.slice(0, 8) + "…";
  } else if (editorType === "category") {
    display = categories.find((c) => c.id === filter.value)?.name ?? filter.value.slice(0, 8) + "…";
  } else if (editorType === "account") {
    display = accounts.find((a) => a.id === filter.value)?.name ?? filter.value.slice(0, 8) + "…";
  } else if (editorType === "select" && fieldDef?.editor.type === "select") {
    display = fieldDef.editor.options.find((o) => o.value === filter.value)?.label ?? filter.value;
  } else if (editorType === "date") {
    display = filter.operator === "month"
      ? formatMonthLabel(filter.value)
      : new Date(filter.value + "T12:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
  }

  return <span className="rounded bg-muted px-1.5 py-0.5 font-medium">{display}</span>;
}

// ── Value editor (inside popover) ─────────────────────────────────────────────

export function FilterValueEditor({ filter, fieldDef, onUpdate, onDone }: {
  filter: ActiveFilter;
  fieldDef: FieldDef | undefined;
  onUpdate: (patch: Partial<ActiveFilter>) => void;
  onDone: () => void;
}) {
  const editorType = fieldDef?.editor.type;
  const { data: merchants = [] } = useQuery({ ...queries.merchants(), enabled: editorType === "merchant" });
  const { data: categories = [] } = useQuery({ ...queries.categories(), enabled: editorType === "category" });
  const { data: accounts = [] } = useQuery({ ...queries.accounts(), enabled: editorType === "account" });

  const wrap = (children: React.ReactNode) => (
    <div className="p-3 space-y-2 min-w-56">{children}</div>
  );

  if (editorType === "account") {
    return wrap(
      <AccountCombobox
        value={filter.value}
        onChange={(id) => { onUpdate({ value: id }); if (id) onDone(); }}
        accounts={accounts}
        allowCreate={false}
        placeholder="Search account…"
      />
    );
  }

  if (editorType === "merchant") {
    return wrap(
      <MerchantCombobox
        value={filter.value}
        onChange={(id) => { onUpdate({ value: id }); if (id) onDone(); }}
        merchants={merchants}
        placeholder="Search merchant…"
      />
    );
  }

  if (editorType === "category") {
    return wrap(
      <Select
        autoFocus
        value={filter.value}
        onChange={(e) => { onUpdate({ value: e.target.value }); onDone(); }}
        aria-label="Category"
        className="h-8 pl-2"
      >
        <option value="">— Select —</option>
        {categories.filter((c) => c.parent_id === null).map((c) => (
          <option key={c.id} value={c.id}>{c.name}</option>
        ))}
      </Select>
    );
  }

  if (editorType === "select" && fieldDef?.editor.type === "select") {
    const options = fieldDef.editor.options;
    return wrap(
      <div className="space-y-1">
        {options.map(({ value, label }) => (
          <button
            key={value}
            onClick={() => { onUpdate({ value }); onDone(); }}
            className={cn("flex w-full rounded-lg px-3 py-2 text-sm hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
              filter.value === value && "bg-primary/8 font-medium text-primary")}
          >
            {label}
          </button>
        ))}
      </div>
    );
  }

  if (editorType === "date") {
    const isMonth = filter.operator === "month";
    return wrap(
      <>
        <Tabs
          size="sm"
          value={filter.operator}
          onChange={(o) => onUpdate({ operator: o, value: "" })}
          options={[
            { value: "month", label: "Month" },
            { value: "gte", label: "After" },
            { value: "lte", label: "Before" },
          ]}
        />
        <Input
          key={isMonth ? "month" : "date"}
          autoFocus
          type={isMonth ? "month" : "date"}
          value={filter.value}
          onChange={(e) => onUpdate({ value: e.target.value })}
          onKeyDown={(e) => e.key === "Enter" && filter.value && onDone()}
          aria-label={isMonth ? "Month" : "Date"}
          className="h-8 px-2"
        />
        <Button size="sm" className="w-full" onClick={() => filter.value && onDone()} disabled={!filter.value}>
          Apply
        </Button>
      </>
    );
  }

  if (editorType === "amount") {
    return wrap(
      <>
        <Tabs
          size="sm"
          value={filter.operator}
          onChange={(op) => onUpdate({ operator: op })}
          options={[
            { value: "greater_than", label: ">" },
            { value: "equals", label: "=" },
            { value: "less_than", label: "<" },
          ]}
        />
        <Input
          autoFocus
          type="number"
          value={filter.value}
          onChange={(e) => onUpdate({ value: e.target.value })}
          onKeyDown={(e) => e.key === "Enter" && onDone()}
          placeholder="Amount…"
          aria-label="Amount"
          className="h-8 px-2 tabular-nums"
        />
        <Button size="sm" className="w-full" onClick={onDone}>
          Apply
        </Button>
      </>
    );
  }

  // text / fallback
  const placeholder = fieldDef?.editor.type === "text" ? (fieldDef.editor.placeholder ?? "Enter text…") : "Enter text…";
  return wrap(
    <>
      <Input
        autoFocus
        value={filter.value}
        onChange={(e) => onUpdate({ value: e.target.value })}
        onKeyDown={(e) => e.key === "Enter" && onDone()}
        placeholder={placeholder}
        aria-label={fieldDef?.label ?? "Value"}
        className="h-8 px-2"
      />
      <Button size="sm" className="w-full" onClick={onDone}>
        Apply
      </Button>
    </>
  );
}
