import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Pencil, Trash2, Plus, Check, X } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { FieldError } from "@/components/ui/field";
import { SkeletonList } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { useConfirm } from "@/components/ui/confirm";
import { ErrorState } from "@/components/PageState";
import type { Broker } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

export function BrokersSection() {
  const qc = useQueryClient();
  const { data: brokers = [], isLoading, isError, refetch } = useQuery(queries.brokers());

  const [newName, setNewName] = useState("");
  const [error, setError] = useState("");

  const create = useMutation({
    mutationFn: (name: string) => api.post<Broker>("/brokers", { name: name.trim() }),
    onSuccess: () => { invalidate(qc, keys.brokers); setNewName(""); },
    onError: (err: Error) => setError(err.message),
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-semibold text-foreground">Brokers</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <form
          onSubmit={(e) => { e.preventDefault(); if (newName.trim()) { setError(""); create.mutate(newName); } }}
          className="flex items-center gap-2"
        >
          <Input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="e.g. Fidelity, Vanguard, Chase"
            aria-label="Broker name"
            className="h-9 flex-1"
          />
          <Button type="submit" size="sm" disabled={!newName.trim() || create.isPending} className="gap-1.5">
            <Plus size={14} />
            {create.isPending ? "Adding…" : "Add broker"}
          </Button>
        </form>
        <FieldError>{error || null}</FieldError>

        {isLoading && <SkeletonList rows={3} />}
        {isError && <ErrorState title="Failed to load brokers" onRetry={() => refetch()} />}
        {!isLoading && !isError && brokers.length === 0 && (
          <EmptyState title="No brokers yet." description="Add one to start creating accounts." className="py-6" />
        )}
        {brokers.length > 0 && (
          <div className="divide-y rounded-lg border">
            {brokers.map((b) => <BrokerRow key={b.id} broker={b} />)}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function BrokerRow({ broker }: { broker: Broker }) {
  const qc = useQueryClient();
  const confirm = useConfirm();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(broker.name ?? "");
  const [error, setError] = useState("");

  const rename = useMutation({
    mutationFn: () => api.patch<Broker>(`/brokers/${broker.id}`, { name: name.trim() }),
    onSuccess: () => { invalidate(qc, keys.brokers); setEditing(false); setError(""); },
    onError: (err: Error) => setError(err.message),
  });

  const remove = useMutation({
    mutationFn: () => api.delete(`/brokers/${broker.id}`),
    onSuccess: () => invalidate(qc, keys.brokers),
    onError: (err: Error) => setError(err.message),
  });

  return (
    <div className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
      <div className="min-w-0 flex-1">
        {editing ? (
          <Input
            autoFocus
            value={name}
            aria-label="Broker name"
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && name.trim()) rename.mutate();
              if (e.key === "Escape") { setEditing(false); setName(broker.name ?? ""); }
            }}
            className="h-8 max-w-xs"
          />
        ) : (
          <p className="truncate font-medium">{broker.name ?? "—"}</p>
        )}
        <p className="text-xs text-muted-foreground">
          {broker.account_count} {broker.account_count === 1 ? "account" : "accounts"}
        </p>
        <FieldError className="mt-1">{error || null}</FieldError>
      </div>
      <div className="flex items-center gap-1">
        {editing ? (
          <>
            <Button
              size="icon-sm"
              variant="ghost"
              onClick={() => { setEditing(false); setName(broker.name ?? ""); setError(""); }}
              title="Cancel"
              aria-label="Cancel"
            >
              <X size={14} />
            </Button>
            <Button
              size="icon-sm"
              variant="ghost"
              disabled={!name.trim() || rename.isPending}
              onClick={() => rename.mutate()}
              title="Save"
              aria-label="Save"
            >
              <Check size={14} />
            </Button>
          </>
        ) : (
          <>
            <Button size="icon-sm" variant="ghost" onClick={() => setEditing(true)} title="Rename" aria-label="Rename">
              <Pencil size={14} />
            </Button>
            <Button
              size="icon-sm"
              variant="ghost"
              disabled={broker.account_count > 0}
              onClick={async () => {
                if (await confirm({ title: `Delete ${broker.name ?? "this broker"}?`, confirmLabel: "Delete", destructive: true })) {
                  remove.mutate();
                }
              }}
              title={broker.account_count > 0 ? "Has accounts — delete those first" : "Delete"}
              aria-label="Delete broker"
              className="text-destructive hover:bg-destructive/10 hover:text-destructive"
            >
              <Trash2 size={14} />
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
