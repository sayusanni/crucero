import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import type { Branch } from "@/lib/database.types";

export default async function BranchesPage() {
  const profile = await requireArea("operations");
  const supabase = await createClient();
  const { data } = await supabase.from("branches").select("*").order("name");

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="operations" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <h1 className="display text-5xl">Branches</h1>
        <div className="mt-8 grid gap-3">
          {((data as Branch[] | null) ?? []).map((branch) => (
            <article key={branch.id} className="panel rounded-3xl p-5">
              <h2 className="display text-2xl">{branch.name}</h2>
              <p className="text-sm text-ink/70">
                {branch.address}, {branch.city}
              </p>
            </article>
          ))}
        </div>
      </main>
    </div>
  );
}
