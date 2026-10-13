import { SiteNav } from "@/components/nav";
import { ActionForm } from "@/components/form-error";
import { requireArea } from "@/lib/auth";
import { allotVehiclePrice, setVehicleStatus } from "@/lib/actions";
import { createClient } from "@/lib/supabase/server";
import { describeRate, formatInr } from "@/lib/money";
import type { Branch, Vehicle } from "@/lib/database.types";

type RateCard = {
  id: string;
  name: string;
  unit: string;
  unit_rate: number;
  daily_rate: number | null;
  deposit: number;
};

async function statusAction(_prev: string | null, formData: FormData) {
  "use server";
  const result = await setVehicleStatus(formData);
  return result?.error ?? null;
}

async function allotAction(_prev: string | null, formData: FormData) {
  "use server";
  const result = await allotVehiclePrice(formData);
  return result?.error ?? null;
}

export default async function FleetPage() {
  const profile = await requireArea("operations");
  const supabase = await createClient();
  const [{ data: vehicles }, { data: branches }, { data: cards }] = await Promise.all([
    supabase.from("vehicles").select("*").order("kind").order("name"),
    supabase.from("branches").select("*"),
    supabase.from("rate_cards").select("id, name, unit, unit_rate, daily_rate, deposit").eq("is_active", true).order("name"),
  ]);
  const rateCards = (cards ?? []) as RateCard[];
  const branchName = new Map((branches as Branch[] | null)?.map((branch) => [branch.id, branch.name]));

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="operations" />
      <main className="mx-auto max-w-6xl px-5 py-12">
        <h1 className="display text-5xl">Fleet</h1>
        <p className="mt-2 max-w-xl text-sm text-ink/70">
          Each bike and car has its own price. Pick a default to copy those rates, or set custom numbers. A booking already made keeps its snapshot.
        </p>
        <div className="mt-8 space-y-4">
          {((vehicles as Vehicle[] | null) ?? []).map((vehicle) => {
            const cardName = rateCards.find((card) => card.id === vehicle.rate_card_id)?.name;
            return (
              <article key={vehicle.id} className="panel rounded-3xl p-5">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <p className="text-xs uppercase tracking-wider text-moss">
                      {vehicle.status} · {vehicle.kind} · {branchName.get(vehicle.branch_id)}
                    </p>
                    <h2 className="display text-2xl">{vehicle.name}</h2>
                    <p className="text-sm text-ink/65">
                      {vehicle.registration} · {describeRate(vehicle.price_unit, Number(vehicle.unit_rate), Number(vehicle.daily_price))} · deposit{" "}
                      {formatInr(Number(vehicle.deposit))}
                      {cardName ? ` · ${cardName}` : " · custom"}
                    </p>
                  </div>
                  <div className="w-full max-w-xs">
                    <ActionForm
                      action={statusAction}
                      submit={vehicle.status === "maintenance" ? "Mark available" : "Send to workshop"}
                    >
                      <input type="hidden" name="vehicle_id" value={vehicle.id} />
                      <input type="hidden" name="status" value={vehicle.status === "maintenance" ? "available" : "maintenance"} />
                    </ActionForm>
                  </div>
                </div>
                <ActionForm action={allotAction} submit="Allot this price">
                  <div className="grid gap-3 md:grid-cols-3">
                    <label className="text-sm md:col-span-2">
                      Default
                      <select name="rate_card_id" defaultValue={vehicle.rate_card_id ?? "custom"} className="mt-1 w-full rounded-xl px-3 py-2">
                        <option value="custom">Custom</option>
                        {rateCards.map((card) => (
                          <option key={card.id} value={card.id}>
                            {card.name} · {describeRate(card.unit, Number(card.unit_rate), card.daily_rate)}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label className="text-sm">
                      Unit
                      <select name="unit" defaultValue={vehicle.price_unit} className="mt-1 w-full rounded-xl px-3 py-2">
                        <option value="hour">Hour</option>
                        <option value="minute">Minute</option>
                        <option value="km">Km</option>
                      </select>
                    </label>
                    <label className="text-sm">
                      Rate
                      <input name="unit_rate" type="number" min="0" step="0.01" defaultValue={Number(vehicle.unit_rate)} className="mt-1 w-full rounded-xl px-3 py-2" />
                    </label>
                    <label className="text-sm">
                      Daily
                      <input name="daily_rate" type="number" min="0" step="0.01" defaultValue={Number(vehicle.daily_price)} className="mt-1 w-full rounded-xl px-3 py-2" />
                    </label>
                    <label className="text-sm">
                      Deposit
                      <input name="deposit" type="number" min="0" step="0.01" defaultValue={Number(vehicle.deposit)} className="mt-1 w-full rounded-xl px-3 py-2" />
                    </label>
                  </div>
                  <input type="hidden" name="vehicle_id" value={vehicle.id} />
                </ActionForm>
              </article>
            );
          })}
        </div>
      </main>
    </div>
  );
}
