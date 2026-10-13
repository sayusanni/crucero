import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export default async function DocumentsPage() {
  const profile = await requireArea("backend");
  const supabase = await createClient();
  const { data } = await supabase.from("documents").select("id, kind, last4, storage_path, created_at").order("created_at", { ascending: false });

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="backend" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Backend</p>
        <h1 className="display mt-3 text-5xl">Documents</h1>
        <p className="mt-3 text-ink/70">
          Licence files stay in a private bucket. The ID column accepts four characters. A 12-digit Aadhaar number is rejected before it is stored.
        </p>
        <div className="mt-8 space-y-2">
          {(data ?? []).length === 0 ? <p className="text-sm text-ink/60">No documents uploaded yet.</p> : null}
          {(data ?? []).map((doc) => (
            <article key={doc.id} className="panel rounded-2xl p-4 text-sm">
              <p className="font-medium">{doc.kind}</p>
              <p className="text-ink/70">{doc.kind === "id_last4" ? `Last 4: ${doc.last4}` : "File stored. Path is private to the customer folder."}</p>
            </article>
          ))}
        </div>
      </main>
    </div>
  );
}
