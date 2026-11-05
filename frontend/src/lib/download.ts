/** Save `content` from memory as a file named `filename`. */
export function downloadText(filename: string, content: string, type = "text/plain;charset=utf-8"): void {
  const url = URL.createObjectURL(new Blob([content], { type }));
  clickLink(url, filename);
  URL.revokeObjectURL(url);
}

/** Hand a URL to the browser's own download machinery — for files too big
 *  to pull through fetch into memory. The response names the file itself
 *  (Content-Disposition), so the page stays where it is. */
export function downloadUrl(url: string): void {
  clickLink(url);
}

function clickLink(href: string, filename?: string): void {
  const a = document.createElement("a");
  a.href = href;
  if (filename) a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
}
