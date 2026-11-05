import { useState } from "react";
import { Navigate, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { FinMark } from "@/components/FinMark";
import { api } from "@/api/client";
import { queries } from "@/api/queries";
import type { FogConnection, FogConnectionAnswer } from "@/api/types";
import { formatDateTime } from "@/lib/utils";

/** /connect/<ticket> — fog sent a household admin here to say whether
 *  another app on the box may read Fin (fog-integration/1 consent).
 *  Approving mints a read-only API token in their name for that app;
 *  either answer takes the browser back to fog. */
export function ConnectApp() {
  const { ticket = "" } = useParams();
  const { data, isLoading, error } = useQuery(queries.fogConnection(ticket));
  const [busy, setBusy] = useState<"approve" | "decline" | null>(null);
  const [answerError, setAnswerError] = useState<string | null>(null);

  async function answer(verb: "approve" | "decline") {
    setAnswerError(null);
    setBusy(verb);
    try {
      const answered = await api.post<FogConnectionAnswer>(`/fog_connections/${encodeURIComponent(ticket)}/${verb}`);
      window.location.assign(answered.return_to);
    } catch (e) {
      setAnswerError((e as Error).message || "That didn't work. Try again from fog.");
      setBusy(null);
    }
  }

  if (isLoading) {
    return (
      <ConnectCard>
        <Skeleton className="mx-auto h-6 w-48" />
        <Skeleton className="h-16 w-full" />
      </ConnectCard>
    );
  }

  if (error || !data) {
    return (
      <ConnectCard>
        <h1 className="text-center text-xl font-semibold tracking-tight">Nothing to connect</h1>
        <p role="alert" className="text-center text-sm text-muted-foreground">
          {(error as Error | null)?.message || "This request is gone. Connect the app in fog again."}
        </p>
      </ConnectCard>
    );
  }

  return (
    <ConnectCard>
      <div className="space-y-1 text-center">
        <h1 className="text-xl font-semibold tracking-tight">Let {data.consumer} read Fin?</h1>
        <p className="text-sm text-muted-foreground">
          fog is asking for <span className="font-medium text-foreground">{data.consumer}</span> to have{" "}
          <span className="font-medium text-foreground">{data.offer.title}</span>.
        </p>
      </div>

      <p className="rounded-lg border bg-muted/30 p-3 text-sm text-muted-foreground">{data.offer.blurb}</p>

      {data.state === "pending" ? (
        <div className="space-y-3">
          <p className="text-center text-caption text-muted-foreground">
            A read-only token in your name, listed with your API tokens. This request expires {formatDateTime(data.expires_at)}.
          </p>
          {answerError && (
            <p role="alert" className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{answerError}</p>
          )}
          <div className="flex gap-2">
            <Button variant="outline" className="flex-1" onClick={() => void answer("decline")} disabled={busy !== null}>
              Decline
            </Button>
            <Button className="flex-1 gap-2" onClick={() => void answer("approve")} disabled={busy !== null}>
              {busy === "approve" && <Loader2 size={14} className="animate-spin" />}
              Approve
            </Button>
          </div>
        </div>
      ) : (
        <p className="text-center text-sm text-muted-foreground">{settled(data)}</p>
      )}
    </ConnectCard>
  );
}

/** Why a request can no longer be answered. */
function settled(data: FogConnection): string {
  switch (data.state) {
    case "expired":
      return "This request expired before anyone answered it. Connect the app in fog again.";
    case "declined":
      return "This request was declined.";
    default:
      return `This request was already approved; ${data.consumer} is connected.`;
  }
}

/** The same address without a session: sign in first, then come back. */
export function ConnectAppSignin() {
  const { ticket = "" } = useParams();
  return <Navigate to={{ pathname: "/login", hash: `return_to=${encodeURIComponent(`/connect/${ticket}`)}` }} replace />;
}

function ConnectCard({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
      <div className="w-full max-w-sm space-y-6 rounded-2xl border bg-card p-8 shadow-sm">
        <FinMark className="mx-auto size-12" />
        {children}
      </div>
    </div>
  );
}
