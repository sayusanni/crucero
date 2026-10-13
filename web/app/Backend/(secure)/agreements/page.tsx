import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatWhen } from "@/lib/time";

export default async function AgreementsPage() {
  const profile = await requireArea("backend");
  const supabase = await createClient();
  const { data } = await supabase
    .from("agreements")
    .select("id, status, signed_at, body, bookings(status)")
    .order("signed_at", { ascending: false });

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="backend" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Backend</p>
        <h1 className="display mt-3 text-5xl">Agreements</h1>
        <p className="mt-3 text-ink/70">Signed only after payment is authorized, and before capture.</p>
        <div className="mt-8 space-y-3">
          {(data ?? []).length === 0 ? <p className="text-sm text-ink/60">No agreements signed yet.</p> : null}
          {(data ?? []).map((row) => (
            <article key={row.id} className="panel rounded-3xl p-5 text-sm">
              <p className="text-xs uppercase tracking-wider text-ember">{row.status}</p>
              <p className="mt-2 whitespace-pre-wrap text-ink/80">{row.body}</p>
              {row.signed_at ? <p className="mt-2 text-xs text-ink/50">Signed {formatWhen(row.signed_at)}</p> : null}
            </article>
          ))}
        </div>
      </main>
    </div>
  );
}
