import { getToken } from "@/api/client";
import type { Import, ImportPreview } from "@/api/types";

/** POSTs to an import endpoint and answers the Import either way: a failed
 *  import comes back 422 with the import itself as the body, its reason in
 *  `error_log`, and that reason is the useful thing to show — not "HTTP 422".
 *  Anything else that isn't 2xx throws with the server's message. */
export async function postImport(path: string, body: FormData | Record<string, unknown>): Promise<Import> {
  const form = body instanceof FormData;
  const res = await fetch(`/api/v1${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getToken()}`,
      ...(form ? {} : { "Content-Type": "application/json" }),
    },
    body: form ? body : JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (res.ok || (res.status === 422 && json?.status === "failed")) return json as Import;
  throw new Error(json.error || json.errors?.join(", ") || `HTTP ${res.status}`);
}

/** Checks a CSV against the import formats without importing it. */
export async function previewFile(file: File, accountId: string): Promise<ImportPreview> {
  const form = new FormData();
  form.append("file", file);
  form.append("account_id", accountId);
  const res = await fetch("/api/v1/imports/preview", {
    method: "POST",
    headers: { Authorization: `Bearer ${getToken()}` },
    body: form,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json.error || json.errors?.join(", ") || `HTTP ${res.status}`);
  return json as ImportPreview;
}
