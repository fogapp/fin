import { useState } from "react";
import { ArrowDown, ArrowUp, X } from "lucide-react";
import { useTimeframeButtons } from "@/hooks/useTimeframeButtons";
import {
  BUILTIN_TIMEFRAMES, BUILTIN_TIMEFRAME_KEYS, TimeframeSelector, builtinOption,
  type BuiltinTimeframe, type TimeframeOption,
} from "@/components/charts";
import {
  MAX_LABEL_LENGTH, MAX_ROLLING_AMOUNT, ROLLING_UNITS, TIMEFRAME_PAGES,
  buttonKey, pageDefaultKey, fixedDescription, newButtonId, rollingDescription, suggestFixedLabel, suggestRollingLabel,
  type RollingUnit, type TimeframeButtonConfig, type TimeframePage,
} from "@/components/charts/timeframeButtons";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Tabs } from "@/components/ui/tabs";
import { formatDate } from "@/lib/utils";
import { SettingsSection, SettingsSubsection, SettingsResetButton } from "@/pages/settings/SettingsSection";

export function TimeframeSettings() {
  const { settings, options, isCustomized, save } = useTimeframeButtons();
  const [preview, setPreview] = useState<string | null>(null);
  const { buttons, defaults } = settings;

  // Removing a button leaves any page default pointing at it in place — the
  // page falls back to its built-in default (pageDefaultKey), and the
  // preferences endpoint deep-merges, so dropping keys wouldn't persist anyway.
  const setButtons = (next: TimeframeButtonConfig[]) => save({ buttons: next, defaults });
  const setPageDefault = (page: TimeframePage, key: string) =>
    save({ buttons, defaults: { ...defaults, [page]: key } });

  function move(index: number, delta: -1 | 1) {
    const next = [...buttons];
    [next[index], next[index + delta]] = [next[index + delta], next[index]];
    setButtons(next);
  }

  const previewKey = preview && options.some((o) => o.key === preview) ? preview : pageDefaultKey(settings, "cashflow");

  return (
    <SettingsSection
      title="Timeframe buttons"
      description="The buttons in the timeframe control on every page that has one: Cashflow, Net Worth, Investments, Categories, Tags, and Stats. A Custom date range is always offered after them."
    >
      <SettingsSubsection label="Preview">
        <TimeframeSelector value={previewKey} onChange={setPreview} options={options} />
      </SettingsSubsection>

      <SettingsSubsection label="Buttons">
        <ul className="divide-y rounded-xl border">
          {buttons.map((b, i) => (
            <ButtonRow
              key={buttonKey(b)}
              option={options[i]}
              onMoveUp={i > 0 ? () => move(i, -1) : undefined}
              onMoveDown={i < buttons.length - 1 ? () => move(i, 1) : undefined}
              onRemove={buttons.length > 1 ? () => setButtons(buttons.filter((_, j) => j !== i)) : undefined}
            />
          ))}
        </ul>
      </SettingsSubsection>

      <SettingsSubsection label="Add a button">
        <AddButtonForm existing={buttons} onAdd={(b) => setButtons([...buttons, b])} />
      </SettingsSubsection>

      <SettingsSubsection
        label="Default for each page"
        description="The button selected when you first open the page. Your pick sticks for the rest of the browser session."
      >
        <div className="divide-y rounded-xl border">
          {TIMEFRAME_PAGES.map((page) => (
            <div key={page.id} className="flex items-center justify-between gap-4 px-4 py-2.5">
              <label htmlFor={`tf-default-${page.id}`} className="text-sm font-medium">{page.label}</label>
              <Select
                id={`tf-default-${page.id}`}
                value={pageDefaultKey(settings, page.id)}
                onChange={(e) => setPageDefault(page.id, e.target.value)}
                wrapperClassName="w-56"
                className="h-8"
              >
                {options.map((o) => (
                  <option key={o.key} value={o.key}>{o.label} · {o.description}</option>
                ))}
              </Select>
            </div>
          ))}
        </div>
      </SettingsSubsection>

      {isCustomized && <SettingsResetButton onClick={() => { setPreview(null); save(null); }} />}
    </SettingsSection>
  );
}

function ButtonRow({ option, onMoveUp, onMoveDown, onRemove }: {
  option: TimeframeOption;
  onMoveUp?: () => void;
  onMoveDown?: () => void;
  onRemove?: () => void;
}) {
  return (
    <li className="flex items-center gap-3 px-3 py-2">
      <span className="w-14 shrink-0 truncate rounded-md bg-muted/60 px-2 py-0.5 text-center text-xs font-medium">
        {option.label}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm">{option.description}</p>
        <p className="truncate text-xs text-muted-foreground">
          {option.from && option.to ? `${formatDate(option.from)} – ${formatDate(option.to)}` : "Everything on record"}
        </p>
      </div>
      <div className="flex shrink-0 items-center">
        <Button variant="ghost" size="icon-sm" aria-label={`Move ${option.label} up`} disabled={!onMoveUp} onClick={onMoveUp}>
          <ArrowUp size={14} />
        </Button>
        <Button variant="ghost" size="icon-sm" aria-label={`Move ${option.label} down`} disabled={!onMoveDown} onClick={onMoveDown}>
          <ArrowDown size={14} />
        </Button>
        <Button variant="ghost" size="icon-sm" aria-label={`Remove ${option.label}`} disabled={!onRemove} onClick={onRemove}>
          <X size={14} />
        </Button>
      </div>
    </li>
  );
}

type AddKind = "preset" | "rolling" | "fixed";

const ADD_KINDS: { value: AddKind; label: string }[] = [
  { value: "preset",  label: "Preset" },
  { value: "rolling", label: "Last N…" },
  { value: "fixed",   label: "Date range" },
];

function AddButtonForm({ existing, onAdd }: {
  existing: TimeframeButtonConfig[];
  onAdd: (b: TimeframeButtonConfig) => void;
}) {
  const [kind, setKind] = useState<AddKind>("preset");
  const [label, setLabel] = useState("");
  const available = BUILTIN_TIMEFRAME_KEYS.filter(
    (k) => !existing.some((b) => b.type === "builtin" && b.key === k),
  );
  const [presetChoice, setPresetChoice] = useState<BuiltinTimeframe | "">("");
  const preset = presetChoice && available.includes(presetChoice) ? presetChoice : available[0];
  const [amount, setAmount] = useState("2");
  const [unit, setUnit] = useState<RollingUnit>("years");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const amountNum = Number(amount);
  const amountValid = Number.isInteger(amountNum) && amountNum >= 1 && amountNum <= MAX_ROLLING_AMOUNT;
  const [lo, hi] = from <= to ? [from, to] : [to, from];

  let suggested = "";
  let summary = "";
  if (kind === "rolling" && amountValid) {
    suggested = suggestRollingLabel(amountNum, unit);
    summary = rollingDescription(amountNum, unit);
  } else if (kind === "fixed" && from && to) {
    suggested = suggestFixedLabel(lo, hi);
    summary = fixedDescription(lo, hi);
  }
  const finalLabel = (label.trim() || suggested).slice(0, MAX_LABEL_LENGTH);

  function add() {
    if (kind === "preset") {
      if (preset) onAdd({ type: "builtin", key: preset });
      setPresetChoice("");
      return;
    }
    if (!finalLabel) return;
    if (kind === "rolling") {
      if (!amountValid) return;
      onAdd({ type: "rolling", id: newButtonId(), label: finalLabel, amount: amountNum, unit });
    } else {
      if (!from || !to) return;
      onAdd({ type: "fixed", id: newButtonId(), label: finalLabel, from: lo, to: hi });
    }
    setLabel("");
  }

  const canAdd =
    kind === "preset" ? Boolean(preset)
    : kind === "rolling" ? amountValid && Boolean(finalLabel)
    : Boolean(from && to && finalLabel);

  return (
    <div className="space-y-4 rounded-xl border p-4">
      <Tabs size="sm" aria-label="Button type" value={kind} onChange={setKind} options={ADD_KINDS} />

      {kind === "preset" && (
        available.length === 0 ? (
          <p className="text-sm text-muted-foreground">Every preset is already in the row.</p>
        ) : (
          <Field label="Preset" htmlFor="tf-preset">
            <Select
              id="tf-preset"
              value={preset}
              onChange={(e) => setPresetChoice(e.target.value as BuiltinTimeframe)}
              wrapperClassName="max-w-xs"
            >
              {available.map((k) => (
                <option key={k} value={k}>
                  {BUILTIN_TIMEFRAMES[k].description} ({builtinOption(k).label})
                </option>
              ))}
            </Select>
          </Field>
        )
      )}

      {kind === "rolling" && (
        <div className="flex flex-wrap items-start gap-3">
          <Field label="Last" htmlFor="tf-amount" className="w-20" error={amount && !amountValid ? `1–${MAX_ROLLING_AMOUNT}` : null}>
            <Input
              id="tf-amount"
              type="number"
              min={1}
              max={MAX_ROLLING_AMOUNT}
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </Field>
          <Field label="Unit" htmlFor="tf-unit" className="w-32">
            <Select id="tf-unit" value={unit} onChange={(e) => setUnit(e.target.value as RollingUnit)}>
              {ROLLING_UNITS.map((u) => <option key={u.value} value={u.value}>{u.label}</option>)}
            </Select>
          </Field>
        </div>
      )}

      {kind === "fixed" && (
        <div className="flex flex-wrap items-start gap-3">
          <Field label="From" htmlFor="tf-from" className="w-40">
            <Input id="tf-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </Field>
          <Field label="To" htmlFor="tf-to" className="w-40">
            <Input id="tf-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </Field>
        </div>
      )}

      {kind !== "preset" && (
        <Field label="Button label" htmlFor="tf-label" className="max-w-xs">
          <Input
            id="tf-label"
            value={label}
            maxLength={MAX_LABEL_LENGTH}
            placeholder={suggested || "e.g. 2Y"}
            onChange={(e) => setLabel(e.target.value)}
          />
        </Field>
      )}

      <div className="flex items-center gap-3">
        <Button size="sm" onClick={add} disabled={!canAdd}>Add button</Button>
        {summary && <span className="text-xs text-muted-foreground">{summary}</span>}
      </div>
    </div>
  );
}
