import { Component, type ErrorInfo, type ReactNode } from "react";
import { CHUNK_RELOAD_FLAG, isChunkLoadError } from "@/lib/chunkLoad";

interface Props { children: ReactNode }
interface State { error: Error | null }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("React error boundary caught:", error, info.componentStack);
    // A failed dynamic import after a deploy is unrecoverable without the new
    // build — reload once (flag-guarded so a broken build can't loop).
    if (isChunkLoadError(error) && !sessionStorage.getItem(CHUNK_RELOAD_FLAG)) {
      sessionStorage.setItem(CHUNK_RELOAD_FLAG, "1");
      window.location.reload();
    }
  }

  render() {
    if (this.state.error) {
      if (isChunkLoadError(this.state.error)) {
        // If the one automatic reload already happened this session, offer a
        // manual one instead of looping.
        return (
          <div className="flex h-screen items-center justify-center p-8 text-center">
            <div className="max-w-md space-y-3">
              <p className="text-lg font-semibold">This page failed to load</p>
              <p className="text-sm text-muted-foreground">
                Fin was probably updated while this tab was open. Reload to get the latest version.
              </p>
              <button
                className="text-sm underline text-muted-foreground"
                onClick={() => window.location.reload()}
              >
                Reload
              </button>
            </div>
          </div>
        );
      }
      return (
        <div className="flex h-screen items-center justify-center p-8 text-center">
          <div className="space-y-3 max-w-xl">
            <p className="text-lg font-semibold text-destructive">Something went wrong</p>
            <p className="text-sm text-muted-foreground">{this.state.error.message}</p>
            <details className="rounded bg-muted p-3 text-left text-xs text-muted-foreground">
              <summary className="cursor-pointer select-none">Technical details</summary>
              <pre className="mt-2 overflow-auto max-h-64 whitespace-pre-wrap">
                {this.state.error.stack}
              </pre>
            </details>
            <button
              className="text-sm underline text-muted-foreground"
              onClick={() => this.setState({ error: null })}
            >
              Try again
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
