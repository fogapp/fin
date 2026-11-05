import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ErrorBoundary } from "./ErrorBoundary";

function Boom({ message = "kaboom" }: { message?: string }) {
  throw new Error(message);
}

describe("ErrorBoundary", () => {
  let consoleError: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    // React logs the caught error to console.error; silence it.
    consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => consoleError.mockRestore());

  it("renders its children when no error is thrown", () => {
    render(<ErrorBoundary><span>safe</span></ErrorBoundary>);
    expect(screen.getByText("safe")).toBeInTheDocument();
  });

  it("renders the fallback UI when a child throws", () => {
    render(<ErrorBoundary><Boom message="ouch" /></ErrorBoundary>);
    expect(screen.getByText("Something went wrong")).toBeInTheDocument();
    // Message shown inline; full stack lives behind the details toggle.
    expect(screen.getAllByText(/ouch/).length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("Technical details")).toBeInTheDocument();
  });

  it("resets when the Try again button is clicked", async () => {
    let shouldThrow = true;
    function Child() {
      if (shouldThrow) throw new Error("boom");
      return <span>recovered</span>;
    }
    render(<ErrorBoundary><Child /></ErrorBoundary>);
    expect(screen.getByText("Something went wrong")).toBeInTheDocument();

    shouldThrow = false;
    await userEvent.setup().click(screen.getByRole("button", { name: /try again/i }));
    expect(screen.getByText("recovered")).toBeInTheDocument();
  });
});

describe("ErrorBoundary — post-deploy chunk-load failures", () => {
  const CHUNK_MESSAGE =
    "Failed to fetch dynamically imported module: https://fin.test/assets/Dashboard-abc123.js";

  let consoleError: ReturnType<typeof vi.spyOn>;
  let reload: ReturnType<typeof vi.fn>;
  const originalLocation = window.location;

  beforeEach(() => {
    consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    sessionStorage.clear();
    reload = vi.fn();
    Object.defineProperty(window, "location", {
      configurable: true,
      value: { ...originalLocation, reload },
    });
  });

  afterEach(() => {
    consoleError.mockRestore();
    Object.defineProperty(window, "location", { configurable: true, value: originalLocation });
  });

  it("reloads once when a dynamic import fails and sets the session guard", () => {
    render(<ErrorBoundary><Boom message={CHUNK_MESSAGE} /></ErrorBoundary>);
    expect(reload).toHaveBeenCalledTimes(1);
    expect(sessionStorage.getItem("fin-chunk-reload-attempted")).toBe("1");
  });

  it("does not reload again when the guard is set — shows a friendly reload prompt", () => {
    sessionStorage.setItem("fin-chunk-reload-attempted", "1");
    render(<ErrorBoundary><Boom message={CHUNK_MESSAGE} /></ErrorBoundary>);
    expect(reload).not.toHaveBeenCalled();
    expect(screen.getByText("This page failed to load")).toBeInTheDocument();

    // Manual reload stays available.
    screen.getByRole("button", { name: /reload/i }).click();
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it("never auto-reloads for ordinary errors", () => {
    render(<ErrorBoundary><Boom message="plain crash" /></ErrorBoundary>);
    expect(reload).not.toHaveBeenCalled();
    expect(screen.getByText("Something went wrong")).toBeInTheDocument();
  });
});
