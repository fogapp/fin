import { useEffect } from "react";
import { usePreferences } from "./usePreferences";

export interface FontSizeDef {
  id: string;
  label: string;
  scale: string;
  preview: string;
}

export const FONT_SIZES: FontSizeDef[] = [
  { id: "xs",  label: "XS",     scale: "13px", preview: "text-caption" },
  { id: "sm",  label: "Small",  scale: "14px", preview: "text-xs"     },
  { id: "md",  label: "Medium", scale: "16px", preview: "text-sm"     },
  { id: "lg",  label: "Large",  scale: "18px", preview: "text-base"   },
  { id: "xl",  label: "XL",     scale: "20px", preview: "text-lg"     },
];

export function useFontSize() {
  const { prefs, set } = usePreferences();
  const sizeId = (prefs.font_size as string) ?? localStorage.getItem("font-size") ?? "sm";

  useEffect(() => {
    const def = FONT_SIZES.find((s) => s.id === sizeId) ?? FONT_SIZES[1];
    document.documentElement.style.fontSize = def.scale;
    localStorage.setItem("font-size", sizeId);
  }, [sizeId]);

  function setFontSize(id: string) {
    localStorage.setItem("font-size", id);
    set("font_size", id);
  }

  return { sizeId, setFontSize };
}
