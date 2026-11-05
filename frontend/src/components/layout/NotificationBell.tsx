import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { formatDistanceToNow } from "date-fns";
import { Bell } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { cn } from "@/lib/utils";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import type { AppNotification, NotificationSeverity } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Notification bell ─────────────────────────────────────────────────────────
// Polls /notifications every minute; the badge shows the unread count and the
// panel lists recent notifications with mark-read on click.

const SEVERITY_DOT: Record<NotificationSeverity, string> = {
  info: "bg-primary",
  warning: "bg-warning",
  error: "bg-negative",
  critical: "bg-negative",
};

export function NotificationBell() {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);

  const { data } = useQuery(queries.notifications());
  const notifications = data?.notifications ?? [];
  const unreadCount = data?.unread_count ?? 0;

  const markRead = useMutation({
    mutationFn: (id: string) => api.post(`/notifications/${id}/read`, {}),
    onSuccess: () => invalidate(qc, keys.notifications),
  });

  const markAllRead = useMutation({
    mutationFn: () => api.post("/notifications/read_all", {}),
    onSuccess: () => invalidate(qc, keys.notifications),
  });

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          aria-label={unreadCount > 0 ? `Notifications (${unreadCount} unread)` : "Notifications"}
          className="relative flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
        >
          <Bell size={16} />
          {unreadCount > 0 && (
            <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-primary px-1 text-tiny font-semibold leading-none text-primary-foreground">
              {unreadCount > 99 ? "99+" : unreadCount}
            </span>
          )}
        </button>
      </PopoverTrigger>

      <PopoverContent className="w-80 p-0" aria-label="Notifications">
        <div className="flex items-center justify-between border-b px-3 py-2">
          <p className="text-sm font-medium">Notifications</p>
          {unreadCount > 0 && (
            <button
              onClick={() => markAllRead.mutate()}
              className="text-xs text-muted-foreground hover:text-foreground transition-colors"
            >
              Mark all read
            </button>
          )}
        </div>

        <div className="max-h-96 overflow-y-auto">
          {notifications.length === 0 && (
            <p className="px-3 py-8 text-center text-xs text-muted-foreground">No notifications</p>
          )}
          {notifications.map((n) => (
            <NotificationItem
              key={n.id}
              notification={n}
              onRead={() => markRead.mutate(n.id)}
              onNavigate={() => setOpen(false)}
            />
          ))}
        </div>
      </PopoverContent>
    </Popover>
  );
}

function NotificationItem({ notification: n, onRead, onNavigate }: {
  notification: AppNotification;
  onRead: () => void;
  onNavigate: () => void;
}) {
  const unread = n.read_at === null;
  const navigate = useNavigate();

  return (
    <button
      onClick={() => {
        if (unread) onRead();
        // A notification with a destination opens it (and closes the panel).
        if (n.href) {
          onNavigate();
          navigate(n.href);
        }
      }}
      className={cn(
        "flex w-full items-start gap-2.5 border-b px-3 py-2.5 text-left last:border-b-0 transition-colors",
        unread ? "bg-primary/5 hover:bg-primary/10" : "hover:bg-accent"
      )}
    >
      <span className={cn("mt-1.5 h-2 w-2 shrink-0 rounded-full", SEVERITY_DOT[n.severity] ?? SEVERITY_DOT.info, !unread && "opacity-30")} />
      <span className="min-w-0 flex-1">
        <span className={cn("block truncate text-sm", unread && "font-medium")}>{n.title}</span>
        {n.body && <span className="block truncate text-xs text-muted-foreground">{n.body}</span>}
        <span className="block text-caption text-muted-foreground">
          {formatDistanceToNow(new Date(n.created_at), { addSuffix: true })}
        </span>
      </span>
    </button>
  );
}
