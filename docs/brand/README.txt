FIN — logo kit (S1 Pure Fin)

svg/       Masters. fin-mark.svg = the fin on a transparent background. Mono versions (green / white / black)
           for single-colour use. Lockups = fin + FIN wordmark (text converted to outlines, no font needed).
           fin-app-icon.svg = the fin on the dark green tile.
png/       Transparent PNGs: the fin at 256–2048 px, the lockups at 1800 px wide (horizontal) and 1000 px wide (stacked).
app-store-1024.png  Full-bleed square app icon; iOS rounds the corners itself.
fin-brand-preview.png  The whole kit on one sheet.

Favicons and web app icons live in frontend/public/ (favicon.ico/.svg, favicon-32.png,
apple-touch-icon.png, icon-*.png, site.webmanifest). The 16–48 px favicon uses heavier lines so it stays crisp.

Colours: dark asparagus #3B5A34 · deep #1A3020 · leaf #5A8A4A · highlight #C9E6A6
Wordmark ink: #2B4327 (on light) / #CFE3B6 (on dark). Font: Cormorant Garamond SemiBold, letter-spacing 0.3em.

HTML <head> snippet (as used in frontend/index.html):
<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">

site.webmanifest sets theme_color #2f4f2a.
