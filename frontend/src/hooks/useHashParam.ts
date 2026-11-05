import { useLocation, useNavigate } from "react-router-dom";

export function useHashParam(
  key: string,
  { replace = false }: { replace?: boolean } = {},
): [string | null, (value: string | null) => void] {
  const location = useLocation();
  const navigate = useNavigate();

  const params = new URLSearchParams(location.hash.slice(1));
  const value = params.get(key);

  function setValue(newValue: string | null) {
    // Read window.location.hash directly — it's updated synchronously by the
    // browser's history API, so it reflects any navigate() calls that have
    // already fired in the same event loop tick, avoiding stale-closure issues.
    // Under MemoryRouter (tests) window.location never changes, so fall back
    // to the router's own location to avoid wiping other hash params.
    const next = new URLSearchParams((window.location.hash || location.hash).slice(1));
    if (newValue === null) {
      next.delete(key);
    } else {
      next.set(key, newValue);
    }
    navigate({ hash: next.toString() || "" }, { replace });
  }

  return [value, setValue];
}
