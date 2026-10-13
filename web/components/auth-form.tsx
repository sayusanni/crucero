"use client";

import { useActionState } from "react";
import { signIn, signUp } from "@/lib/actions";
import type { Area } from "@/lib/areas";

type Mode = "login" | "signup";

async function loginAction(_prev: string | null, formData: FormData) {
  const result = await signIn(formData);
  return result?.error ?? null;
}

async function signupAction(_prev: string | null, formData: FormData) {
  const result = await signUp(formData);
  return result?.error ?? null;
}

export function AuthForm({
  mode,
  area,
  asAdmin = false,
  next,
}: {
  mode: Mode;
  area: Area;
  asAdmin?: boolean;
  next: string;
}) {
  const action = mode === "login" ? loginAction : signupAction;
  const [error, formAction, pending] = useActionState(action, null);

  return (
    <form action={formAction} className="panel mx-auto w-full max-w-md space-y-4 rounded-3xl p-8">
      <input type="hidden" name="area" value={area} />
      <input type="hidden" name="next" value={next} />
      <input type="hidden" name="as_admin" value={asAdmin ? "true" : "false"} />
      {mode === "signup" ? (
        <label className="block text-sm">
          Full name
          <input name="full_name" required className="mt-1 w-full rounded-xl px-3 py-2" />
        </label>
      ) : null}
      <label className="block text-sm">
        Email
        <input name="email" type="email" required className="mt-1 w-full rounded-xl px-3 py-2" />
      </label>
      <label className="block text-sm">
        Password
        <input name="password" type="password" minLength={6} required className="mt-1 w-full rounded-xl px-3 py-2" />
      </label>
      {error ? <p className="text-sm text-red-300">{error}</p> : null}
      <button disabled={pending} className="w-full rounded-full bg-ember py-3 text-paper">
        {pending ? "Please wait..." : mode === "login" ? "Sign in" : asAdmin ? "Create admin" : "Create account"}
      </button>
    </form>
  );
}
