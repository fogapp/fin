import { usePreferences } from "@/hooks/usePreferences";
import { useTimeframe, type Timeframe } from "@/components/charts";
import {
  pageDefaultKey, parseTimeframeSettings, resolveButton,
  type TimeframePage, type TimeframeSettings,
} from "@/components/charts/timeframeButtons";

/**
 * The shared timeframe button row, persisted under `timeframes` in the
 * preferences store. Nothing saved (or `null`) means the default row.
 */
export function useTimeframeButtons() {
  const { prefs, set } = usePreferences();
  const { settings, isCustomized } = parseTimeframeSettings(prefs["timeframes"]);

  const today = new Date();
  const options = settings.buttons.map((b) => resolveButton(b, today));

  /** Persist new settings; `null` resets everything to the defaults. */
  const save = (next: TimeframeSettings | null) => set("timeframes", next);

  return { settings, options, isCustomized, save };
}

/** A page's timeframe state over the shared, user-configured button row
 *  (Settings → Timeframes), opening on that page's default button. */
export function usePageTimeframe(page: TimeframePage, storageKey: string): Timeframe {
  const { settings, options } = useTimeframeButtons();
  return useTimeframe({ defaultPreset: pageDefaultKey(settings, page), storageKey, options });
}
