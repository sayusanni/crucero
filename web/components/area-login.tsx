import Link from "next/link";
import { AuthForm } from "@/components/auth-form";
import { SiteNav } from "@/components/nav";
import { AREA_HOME, type Area } from "@/lib/areas";

export function AreaLogin({
  area,
  title,
  blurb,
  denied,
  signupHref,
}: {
  area: Area;
  title: string;
  blurb: string;
  denied?: boolean;
  signupHref?: string;
}) {
  return (
    <div className="yard min-h-svh">
      <SiteNav profile={null} area={area} />
      <main className="px-5 py-16">
        <p className="text-center text-xs uppercase tracking-[0.22em] text-ember">{AREA_HOME[area]}</p>
        <h1 className="display mb-3 text-center text-5xl">{title}</h1>
        <p className="mx-auto mb-8 max-w-md text-center text-sm text-ink/70">{blurb}</p>
        {denied ? (
          <p className="mx-auto mb-4 max-w-md rounded-2xl bg-ember/10 px-4 py-3 text-center text-sm">
            That account is signed in somewhere else. This desk has its own login.
          </p>
        ) : null}
        <AuthForm mode="login" area={area} next={AREA_HOME[area]} />
        {signupHref ? (
          <p className="mt-6 text-center text-sm">
            New here? <Link href={signupHref}>Create an account</Link>
          </p>
        ) : null}
      </main>
    </div>
  );
}
