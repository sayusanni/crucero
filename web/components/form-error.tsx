"use client";

import { useActionState, type ReactNode } from "react";

export function ActionForm({
  action,
  children,
  submit,
}: {
  action: (prev: string | null, formData: FormData) => Promise<string | null>;
  children: ReactNode;
  submit: string;
}) {
  const [error, formAction, pending] = useActionState(action, null);
  return (
    <form action={formAction} className="space-y-3">
      {children}
      {error ? <p className="text-sm text-ember">{error}</p> : null}
      <button disabled={pending} className="w-full rounded-full bg-ember py-3 text-paper">
        {pending ? "Working..." : submit}
      </button>
    </form>
  );
}
