const TOKEN_KEY = "fin_api_token";
// Fin was Manor until 2026-11; a browser signed in before the rename holds its
// token under the old key. Read once, moved to the new key.
const LEGACY_TOKEN_KEY = "manor_api_token";

export function getToken(): string | null {
  const token = localStorage.getItem(TOKEN_KEY);
  if (token !== null) return token;

  const legacy = localStorage.getItem(LEGACY_TOKEN_KEY);
  if (legacy !== null) {
    localStorage.setItem(TOKEN_KEY, legacy);
    localStorage.removeItem(LEGACY_TOKEN_KEY);
  }
  return legacy;
}

export function setToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken() {
  localStorage.removeItem(TOKEN_KEY);
}

async function request<T>(path: string, options: RequestInit = {}, anonymous = false): Promise<T> {
  const token = anonymous ? null : getToken();
  const res = await fetch(`/api/v1${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });

  // A 401 on an anonymous request isn't an expired session — surface the
  // server's error message like any other failure instead of "unauthorized".
  if (res.status === 401 && !anonymous) throw new Error("unauthorized");
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || body.errors?.join(", ") || `HTTP ${res.status}`);
  }

  if (res.status === 204) return undefined as T;
  return res.json() as Promise<T>;
}

/** Extra per-request options. `signal` (React Query's queryFn AbortSignal)
 *  lets in-flight requests be cancelled when the query is superseded —
 *  important for per-keystroke lookups and the paged transaction stream. */
export interface RequestOptions {
  signal?: AbortSignal;
  /** Skip the Authorization header — pre-auth endpoints (passkey ceremonies). */
  anonymous?: boolean;
}

export const api = {
  get: <T>(path: string, opts?: RequestOptions) =>
    request<T>(path, { signal: opts?.signal }, opts?.anonymous),
  post: <T>(path: string, body?: unknown, opts?: RequestOptions) =>
    request<T>(path, { method: "POST", body: JSON.stringify(body), signal: opts?.signal }, opts?.anonymous),
  // Multipart upload (backup artifacts): no Content-Type header — the
  // browser sets the multipart boundary itself.
  upload: async <T>(path: string, form: FormData): Promise<T> => {
    const res = await fetch(`/api/v1${path}`, { method: "POST", body: form });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.error || body.errors?.join(", ") || `HTTP ${res.status}`);
    }
    return res.json() as Promise<T>;
  },
  put: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "PUT", body: JSON.stringify(body) }),
  patch: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "PATCH", body: JSON.stringify(body) }),
  delete: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "DELETE", ...(body !== undefined ? { body: JSON.stringify(body) } : {}) }),
};
