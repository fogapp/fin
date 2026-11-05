/**
 * Chart → PNG export, no dependencies: clone the card's rendered SVG, inline
 * the computed styles (theme colors live in CSS custom properties, which a
 * serialized SVG can't resolve), optionally mask dollar amounts, rasterize
 * through a canvas at 2× and trigger a download.
 */

// The style subset that determines how chart SVGs actually paint. Copying
// everything getComputedStyle knows is ~350 properties per node; these are
// the ones recharts and our custom nodes rely on.
const COPIED_PROPS = [
  "fill", "fill-opacity", "stroke", "stroke-width", "stroke-opacity",
  "stroke-dasharray", "stroke-linejoin", "stroke-linecap", "opacity",
  "font-family", "font-size", "font-weight", "letter-spacing",
  "text-anchor", "dominant-baseline", "color", "visibility",
] as const;

/** Currency-looking runs: $1,234.56 · -$4.5K · $12M. */
const AMOUNT_RE = /-?\$[\d,.]+\s?[KMB]?/g;

function inlineStyles(source: Element, target: Element): void {
  const sourceNodes = [source, ...source.querySelectorAll("*")];
  const targetNodes = [target, ...target.querySelectorAll("*")];
  for (let i = 0; i < sourceNodes.length; i++) {
    const computed = window.getComputedStyle(sourceNodes[i]);
    const style = (targetNodes[i] as HTMLElement | SVGElement).style;
    for (const prop of COPIED_PROPS) style.setProperty(prop, computed.getPropertyValue(prop));
  }
}

function maskAmounts(root: Element): void {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.textContent && AMOUNT_RE.test(node.textContent)) {
      node.textContent = node.textContent.replace(AMOUNT_RE, "•••");
    }
  }
}

/** Serialize the first SVG inside `container` and return it as a PNG blob,
 *  or null when the container holds no chart. Exported for tests. */
export async function chartToPngBlob(container: HTMLElement, { hideAmounts = false, scale = 2 }: {
  hideAmounts?: boolean;
  scale?: number;
} = {}): Promise<Blob | null> {
  const svg = container.querySelector("svg");
  if (!svg) return null;

  const rect = svg.getBoundingClientRect();
  const width = Math.max(1, Math.round(rect.width));
  const height = Math.max(1, Math.round(rect.height));

  const clone = svg.cloneNode(true) as SVGSVGElement;
  clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");
  clone.setAttribute("width", String(width));
  clone.setAttribute("height", String(height));
  inlineStyles(svg, clone);
  if (hideAmounts) maskAmounts(clone);

  const markup = new XMLSerializer().serializeToString(clone);
  const svgUrl = URL.createObjectURL(new Blob([markup], { type: "image/svg+xml;charset=utf-8" }));
  try {
    const image = await new Promise<HTMLImageElement>((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error("Could not rasterize the chart"));
      img.src = svgUrl;
    });

    const canvas = document.createElement("canvas");
    canvas.width = width * scale;
    canvas.height = height * scale;
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    // Paint the card's ground so the PNG isn't transparent-on-unknown; fall
    // back to the page body's themed background rather than a literal color.
    ctx.fillStyle = window.getComputedStyle(container).backgroundColor
      || window.getComputedStyle(document.body).backgroundColor
      || "white";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height);

    return await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/png"));
  } finally {
    URL.revokeObjectURL(svgUrl);
  }
}

/** Slug a chart title into a filename: "Money flow" → money-flow.png. */
export function chartFilename(title: string): string {
  const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "chart";
  return `${slug}.png`;
}

export async function downloadChartPng(container: HTMLElement, title: string, opts?: { hideAmounts?: boolean }): Promise<boolean> {
  const blob = await chartToPngBlob(container, opts);
  if (!blob) return false;
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = chartFilename(title);
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
  return true;
}
