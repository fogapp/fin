import { useEffect } from "react";
import { usePreferences } from "./usePreferences";

export interface FontDef {
  id: string;
  label: string;
  stack: string;
}

export const FONTS: FontDef[] = [
  { id: "system",   label: "System",        stack: "ui-sans-serif, system-ui, -apple-system, sans-serif" },
  { id: "inter",    label: "Inter",         stack: "'Inter', sans-serif" },
  { id: "dm-sans",  label: "DM Sans",       stack: "'DM Sans', sans-serif" },
  { id: "nunito",   label: "Nunito",        stack: "'Nunito', sans-serif" },
  { id: "ibm-plex", label: "IBM Plex Sans", stack: "'IBM Plex Sans', sans-serif" },
  { id: "outfit",   label: "Outfit",        stack: "'Outfit', sans-serif" },
];

export function useFont() {
  const { prefs, set } = usePreferences();
  const fontId = (prefs.font as string) ?? localStorage.getItem("font") ?? "nunito";

  useEffect(() => {
    document.documentElement.setAttribute("data-font", fontId);
    localStorage.setItem("font", fontId);
  }, [fontId]);

  function setFont(id: string) {
    localStorage.setItem("font", id);
    set("font", id);
  }

  return { fontId, setFont };
}
