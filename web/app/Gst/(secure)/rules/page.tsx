import { SiteNav } from "@/components/nav";
import { ActionForm } from "@/components/form-error";
import { requireArea } from "@/lib/auth";
import { addTaxRule } from "@/lib/actions";
import { createClient } from "@/lib/supabase/server";

async function saveRule(_prev: string | null, formData: FormData) {
  "use server";
  const result = await addTaxRule(formData);
  return result?.error ?? null;
}

export default async function TaxRulesPage() {
  const profile = await requireArea("gst");
  const supabase = await createClient();
  const { data: rules } = await supabase
    .from("tax_rules")
    .select("id, name, sac, rate_percent, effective_from, effective_to, is_active")
    .order("effective_from", { ascending: false });

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="gst" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Gst</p>
        <h1 className="display mt-3 text-5xl">Tax rules</h1>
        <p className="mt-3 text-ink/70">
          A new rule closes the open one the day before it starts. Bookings already priced keep their snapshot.
        </p>
        <div className="panel mt-8 rounded-3xl p-6">
          <ActionForm action={saveRule} submit="Add a rule version">
            <label className="block text-sm">
              Name
              <input name="name" required defaultValue="GST on vehicle rental" className="mt-1 w-full rounded-xl px-3 py-2" />
            </label>
            <label className="block text-sm">
              SAC
              <input name="sac" required defaultValue="997329" className="mt-1 w-full rounded-xl px-3 py-2" />
            </label>
            <label className="block text-sm">
              Rate percent
              <input name="rate" type="number" min="0" step="0.01" required className="mt-1 w-full rounded-xl px-3 py-2" />
            </label>
            <label className="block text-sm">
              Effective from
              <input name="effective_from" type="date" required className="mt-1 w-full rounded-xl px-3 py-2" />
            </label>
          </ActionForm>
        </div>
        <div className="mt-8 space-y-2">
          {(rules ?? []).map((rule) => (
            <article key={rule.id} className="panel rounded-2xl p-4 text-sm">
              <p className="font-medium">{rule.name}</p>
              <p className="text-ink/70">
                SAC {rule.sac} · {rule.rate_percent}% · {rule.effective_from}
                {rule.effective_to ? ` to ${rule.effective_to}` : " · open"}
                {rule.is_active ? "" : " · inactive"}
              </p>
            </article>
          ))}
        </div>
      </main>
    </div>
  );
}
