import { cn } from "@/lib/utils";
import { useTheme, THEMES } from "@/hooks/useTheme";
import { useFont, FONTS } from "@/hooks/useFont";
import { useFontSize, FONT_SIZES } from "@/hooks/useFontSize";

export function Appearance() {
  const { theme, setTheme } = useTheme();
  const { fontId, setFont } = useFont();
  const { sizeId, setFontSize } = useFontSize();

  const lightThemes = THEMES.filter((t) => t.type === "light");
  const darkThemes  = THEMES.filter((t) => t.type === "dark");
  const splitThemes = THEMES.filter((t) => t.type === "split");

  const renderSwatch = (t: typeof THEMES[0]) => (
    <button
      key={t.id}
      onClick={() => setTheme(t.id)}
      className={cn(
        "flex flex-col gap-2 rounded-xl border-2 p-3 text-left transition-colors hover:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        theme === t.id ? "border-primary" : "border-border",
      )}
    >
      <div className="h-14 w-full overflow-hidden rounded-lg border" style={{ background: t.bg, borderColor: t.border }}>
        <div className="h-full flex">
          <div className="w-8 h-full" style={{ background: t.sidebarBg ?? t.card, borderRight: `1px solid ${t.sidebarBg ? "transparent" : t.border}` }} />
          <div className="flex-1 p-1.5 space-y-1" style={{ background: t.bg }}>
            <div className="h-1.5 w-3/4 rounded-full" style={{ background: t.border }} />
            <div className="h-1.5 w-1/2 rounded-full" style={{ background: t.border }} />
            <div className="h-1.5 w-2 rounded-full"   style={{ background: t.primary }} />
          </div>
        </div>
      </div>
      <span className="text-xs font-medium">{t.label}</span>
    </button>
  );

  return (
    <div className="space-y-6">
      {/* Font family */}
      <div className="space-y-3">
        <div>
          <p className="text-sm font-medium">Font Family</p>
          <p className="text-xs text-muted-foreground mt-0.5">Interface typeface applied across the whole app.</p>
        </div>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {FONTS.map((f) => (
            <button
              key={f.id}
              onClick={() => setFont(f.id)}
              className={cn(
                "rounded-xl border-2 p-3 text-left transition-colors hover:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                fontId === f.id ? "border-primary" : "border-border",
              )}
            >
              <p className="text-base font-semibold leading-tight" style={{ fontFamily: f.stack }}>Aa</p>
              <p className="text-xs text-muted-foreground mt-1" style={{ fontFamily: f.stack }}>{f.label}</p>
            </button>
          ))}
        </div>
      </div>

      <div className="border-t" />

      {/* Font size */}
      <div className="space-y-3">
        <div>
          <p className="text-sm font-medium">Font Size</p>
          <p className="text-xs text-muted-foreground mt-0.5">Base size applied across the interface.</p>
        </div>
        <div className="grid grid-cols-5 gap-3">
          {FONT_SIZES.map((s) => (
            <button
              key={s.id}
              onClick={() => setFontSize(s.id)}
              className={cn(
                "flex flex-col items-center gap-2 rounded-xl border-2 p-3 transition-colors hover:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                sizeId === s.id ? "border-primary" : "border-border",
              )}
            >
              <span className={cn("font-semibold leading-none", s.preview)}>Aa</span>
              <span className="text-xs text-muted-foreground">{s.label}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="border-t" />

      {/* Interface themes */}
      <div className="space-y-3">
        <div>
          <p className="text-sm font-medium">Interface Theme</p>
          <p className="text-xs text-muted-foreground mt-0.5">Colour theme applied to the entire interface.</p>
        </div>
      </div>

      <div className="space-y-3">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Light</p>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {lightThemes.map(renderSwatch)}
        </div>
      </div>
      <div className="space-y-3">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Dark</p>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {darkThemes.map(renderSwatch)}
        </div>
      </div>
      <div className="space-y-3">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Split</p>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {splitThemes.map(renderSwatch)}
        </div>
      </div>
    </div>
  );
}
