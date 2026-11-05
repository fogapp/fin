import { useEffect } from "react";
import { usePreferences } from "./usePreferences";

export type ThemeId = "light" | "dark" | "midnight" | "sand" | "forest" | "rose" | "ocean" | "dusk" | "lavender" | "mint" | "slate" | "ember" | "eclipse" | "sage" | "plum" | "copper";

export interface ThemeDef {
  id: ThemeId;
  label: string;
  type: "light" | "dark" | "split";
  bg: string;
  card: string;
  border: string;
  primary: string;
  /** For split themes: the dark sidebar card colour */
  sidebarBg?: string;
}

export const THEMES: ThemeDef[] = [
  // Light
  { id: "light",    label: "Light",    type: "light", bg: "hsl(0 0% 100%)",    card: "hsl(0 0% 100%)",    border: "hsl(220 13% 91%)", primary: "hsl(221 83% 53%)" },
  { id: "sand",     label: "Sand",     type: "light", bg: "hsl(40 30% 96%)",   card: "hsl(40 30% 98%)",   border: "hsl(38 20% 82%)",  primary: "hsl(25 90% 45%)"  },
  { id: "forest",   label: "Forest",   type: "light", bg: "hsl(150 20% 97%)",  card: "hsl(150 20% 99%)",  border: "hsl(150 15% 85%)", primary: "hsl(152 60% 35%)" },
  { id: "rose",     label: "Rose",     type: "light", bg: "hsl(340 30% 97%)",  card: "hsl(340 30% 99%)",  border: "hsl(340 20% 88%)", primary: "hsl(340 80% 55%)" },
  { id: "ocean",    label: "Ocean",    type: "light", bg: "hsl(200 30% 97%)",  card: "hsl(200 30% 99%)",  border: "hsl(200 20% 87%)", primary: "hsl(196 80% 42%)" },
  { id: "lavender", label: "Lavender", type: "light", bg: "hsl(270 30% 97%)",  card: "hsl(270 30% 99%)",  border: "hsl(270 20% 88%)", primary: "hsl(270 65% 55%)" },
  { id: "mint",     label: "Mint",     type: "light", bg: "hsl(168 30% 97%)",  card: "hsl(168 30% 99%)",  border: "hsl(168 20% 86%)", primary: "hsl(168 70% 38%)" },
  // Dark
  { id: "dark",     label: "Dark",     type: "dark",  bg: "hsl(224 71% 4%)",   card: "hsl(224 71% 6%)",   border: "hsl(216 34% 17%)", primary: "hsl(217 91% 65%)" },
  { id: "midnight", label: "Midnight", type: "dark",  bg: "hsl(240 10% 4%)",   card: "hsl(240 10% 6%)",   border: "hsl(240 6% 15%)",  primary: "hsl(258 90% 68%)" },
  { id: "dusk",     label: "Dusk",     type: "dark",  bg: "hsl(260 20% 8%)",   card: "hsl(260 20% 11%)",  border: "hsl(260 15% 20%)", primary: "hsl(280 75% 65%)" },
  { id: "slate",    label: "Slate",    type: "dark",  bg: "hsl(215 25% 8%)",   card: "hsl(215 25% 11%)",  border: "hsl(215 20% 18%)", primary: "hsl(210 80% 58%)" },
  { id: "ember",    label: "Ember",    type: "dark",  bg: "hsl(20 20% 6%)",    card: "hsl(20 20% 9%)",    border: "hsl(20 15% 16%)",  primary: "hsl(24 90% 55%)"  },
  // Split
  { id: "eclipse", label: "Eclipse", type: "split", bg: "hsl(0 0% 100%)",   card: "hsl(0 0% 100%)",   border: "hsl(220 13% 91%)", primary: "hsl(221 83% 53%)", sidebarBg: "hsl(224 50% 8%)"  },
  { id: "sage",    label: "Sage",    type: "split", bg: "hsl(150 20% 97%)", card: "hsl(150 20% 99%)", border: "hsl(150 15% 85%)", primary: "hsl(152 60% 35%)", sidebarBg: "hsl(150 30% 10%)" },
  { id: "plum",    label: "Plum",    type: "split", bg: "hsl(270 30% 97%)", card: "hsl(270 30% 99%)", border: "hsl(270 20% 88%)", primary: "hsl(270 65% 55%)", sidebarBg: "hsl(270 35% 10%)" },
  { id: "copper",  label: "Copper",  type: "split", bg: "hsl(40 30% 96%)",  card: "hsl(40 30% 98%)",  border: "hsl(38 20% 82%)",  primary: "hsl(25 90% 45%)",  sidebarBg: "hsl(20 25% 12%)"  },
];

export function useTheme() {
  const { prefs, set } = usePreferences();
  // Fall back to localStorage so the DOM is styled before the API response arrives
  const theme = (prefs.theme as ThemeId) ?? (localStorage.getItem("theme") as ThemeId | null) ?? "copper";

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme === "light" ? "" : theme);
    localStorage.setItem("theme", theme);
  }, [theme]);

  function setTheme(id: ThemeId) {
    localStorage.setItem("theme", id);
    set("theme", id);
  }

  return { theme, setTheme };
}
