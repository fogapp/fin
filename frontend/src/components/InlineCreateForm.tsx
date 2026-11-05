import { useState, type ReactNode } from "react";
import { useMutation, useQueryClient, type QueryKey } from "@tanstack/react-query";
import { api } from "@/api/client";
import { invalidate } from "@/api/keys";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { FieldError } from "@/components/ui/field";

/**
 * The name-and-Add form that opens at the top of a master-detail list (tags,
 * merchants, categories). POSTs `{ name, ...extraBody }` to `endpoint`,
 * refreshes `invalidateKey`, and hands the new id back so the shell can select
 * it. `children` renders extra fields between the name and the buttons.
 */
export function InlineCreateForm({
  endpoint,
  invalidateKey,
  placeholder,
  extraBody,
  onCreated,
  onCancel,
  children,
}: {
  endpoint: string;
  invalidateKey: QueryKey;
  /** Also the input's accessible name, e.g. "Tag name". */
  placeholder: string;
  extraBody?: Record<string, unknown>;
  onCreated: (id: string) => void;
  onCancel: () => void;
  children?: ReactNode;
}) {
  const qc = useQueryClient();
  const [name, setName] = useState("");
  const [error, setError] = useState("");

  const create = useMutation({
    mutationFn: () => api.post<{ id: string }>(endpoint, { name: name.trim(), ...extraBody }),
    onSuccess: (created) => {
      invalidate(qc, invalidateKey);
      onCreated(created.id);
    },
    onError: (err: Error) => setError(err.message),
  });

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    if (!name.trim()) { setError("Name is required"); return; }
    create.mutate();
  }

  return (
    <form onSubmit={submit} className="border-b bg-muted/30 px-3 py-2.5 space-y-1.5">
      <Input
        autoFocus
        value={name}
        onChange={(e) => setName(e.target.value)}
        onKeyDown={(e) => e.key === "Escape" && onCancel()}
        placeholder={placeholder}
        aria-label={placeholder}
        className="h-8"
      />
      {children}
      <FieldError>{error}</FieldError>
      <div className="flex gap-1.5">
        <Button type="button" variant="outline" size="xs" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" size="xs" disabled={create.isPending} className="flex-1">
          {create.isPending ? "Adding…" : "Add"}
        </Button>
      </div>
    </form>
  );
}
