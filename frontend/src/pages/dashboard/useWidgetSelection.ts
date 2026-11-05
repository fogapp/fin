import { usePreferences } from "@/hooks/usePreferences";
import { DEFAULT_WIDGET_IDS, WIDGET_MAP } from "./registry";

/**
 * The user's sidebar widget selection, persisted under `dashboard.widgets`
 * in the preferences store. `null` saved widgets (or none) means "use the
 * defaults"; an explicit selection also switches widgets from hide-when-empty
 * to show-an-empty-state so a hand-picked card never silently disappears.
 */
export function useWidgetSelection() {
  const { prefs, set } = usePreferences();

  const dashPrefs = (typeof prefs["dashboard"] === "object" && prefs["dashboard"] !== null
    ? prefs["dashboard"]
    : {}) as Record<string, unknown>;
  const raw = dashPrefs["widgets"];
  const saved = Array.isArray(raw)
    ? raw.filter((id): id is string => typeof id === "string" && WIDGET_MAP.has(id))
    : null;

  const selected = saved ?? DEFAULT_WIDGET_IDS;
  const isCustomized = saved != null;

  /** Persist a new selection; `null` resets to the defaults. */
  const save = (ids: string[] | null) => {
    set("dashboard", { ...dashPrefs, widgets: ids });
  };

  return { selected, isCustomized, save };
}
