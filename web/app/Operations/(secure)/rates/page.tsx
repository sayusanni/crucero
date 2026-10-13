import { SiteNav } from "@/components/nav";
import { ActionForm } from "@/components/form-error";
import { requireArea } from "@/lib/auth";
import { saveRateCard } from "@/lib/actions";
import { createClient } from "@/lib/supabase/server";
import { describeRate, formatInr } from "@/lib/money";

type RateCard = {
  id: string;
  name: string;
  unit: "hour" | "minute" | "km";
  unit_rate: number;
  daily_rate: number | null;
  deposit: number;
};

async function save(_prev: string | null, formData: FormData) {
  "use server";
  const result = await saveRateCard(formData);
  return result?.error ?? null;
}

export default async function RatesPage() {
  const profile = await requireArea("operations");
  const supabase = await createClient();
  const { data } = await supabase.from("rate_cards").select("*").eq("is_active", true).order("name");
  const cards = (data ?? []) as RateCard[];

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="operations" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Operations</p>
        <h1 className="display mt-3 text-5xl">Default rates</h1>
        <p className="mt-3 text-ink/70">
          Defaults live here. Allotting one onto a bike copies the numbers onto that bike. Editing a default later does not rewrite bikes already priced, and it does not rewrite a booking.
        </p>
        <div className="mt-8 space-y-2">
          {cards.map((card) => (
            <article key={card.id} className="panel rounded-2xl p-4 text-sm">
              <p className="font-medium">{card.name}</p>
              <p className="text-ink/70">
                {describeRate(card.unit, Number(card.unit_rate), card.daily_rate)} · deposit {formatInr(Number(card.deposit))}
              </p>
            </article>
          ))}
        </div>
        <div className="panel mt-8 rounded-3xl p-6">
          <h2 className="display text-2xl">Add a default</h2>
          <div className="mt-4">
            <ActionForm action={save} submit="Save default">
              <label className="block text-sm">
                Name
                <input name="name" required placeholder="Default 6" className="mt-1 w-full rounded-xl px-3 py-2" />
              </label>
              <label className="block text-sm">
                Unit
                <select name="unit" className="mt-1 w-full rounded-xl px-3 py-2">
                  <option value="hour">Per hour</option>
                  <option value="minute">Per minute</option>
                  <option value="km">Per km</option>
                </select>
              </label>
              <label className="block text-sm">
                Rate
                <input name="unit_rate" type="number" min="0" step="0.01" required className="mt-1 w-full rounded-xl px-3 py-2" />
              </label>
              <label className="block text-sm">
                Daily rate, hourly defaults only
                <input name="daily_rate" type="number" min="0" step="0.01" className="mt-1 w-full rounded-xl px-3 py-2" />
              </label>
              <label className="block text-sm">
                Deposit
                <input name="deposit" type="number" min="0" step="0.01" required className="mt-1 w-full rounded-xl px-3 py-2" />
              </label>
            </ActionForm>
          </div>
        </div>
      </main>
    </div>
  );
}
