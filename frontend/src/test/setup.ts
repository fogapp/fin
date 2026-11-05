import "@testing-library/jest-dom";
import { configure } from "@testing-library/react";

// Pages are route-split (React.lazy), so a file's first render also compiles
// the page's module graph on demand. Under a fully parallel suite that can
// exceed the 1s default findBy* timeout; the wait is startup cost, not app
// slowness.
configure({ asyncUtilTimeout: 5000 });

// jsdom doesn't ship ResizeObserver; components that observe resizes need a stub.
if (typeof globalThis.ResizeObserver === "undefined") {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as never;
}

// jsdom doesn't implement scrollIntoView either.
if (typeof Element !== "undefined" && !Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = function () {};
}

// jsdom doesn't ship matchMedia; useIsMobile() etc. depend on it.
if (typeof window !== "undefined" && !window.matchMedia) {
  window.matchMedia = (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  } as MediaQueryList);
}
