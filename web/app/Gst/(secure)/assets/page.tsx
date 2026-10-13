import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import type { Branch, Vehicle } from "@/lib/database.types";

export default async function AssetsPage() {
  const profile = await requireArea("gst");
  const supabase = await createClient();
  const [{ data: vehicles }, { data: branches }, { data: movements }] = await Promise.all([
    supabase.from("vehicles").select("*").order("kind").order("name"),
    supabase.from("branches").select("id, name"),
    supabase.from("bookings").select("vehicle_id, odometer_in, odometer_out, status").in("status", ["out", "returned"]),
  ]);
  const branchName = new Map((branches as Pick<Branch, "id" | "name">[] | null)?.map((branch) => [branch.id, branch.name]));
  const latest = new Map<string, number>();
  for (const row of movements ?? []) {
    const reading = row.odometer_in ?? row.odometer_out;
    if (reading != null) latest.set(row.vehicle_id, Number(reading));
  }

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="gst" />
      <main className="mx-auto max-w-5xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Gst</p>
        <h1 className="display mt-3 text-5xl">Asset register</h1>
        <p className="mt-3 max-w-xl text-ink/70">
          The company owns these bikes and cars. Workshop status is an operations fact. This register only records it.
        </p>
        <div className="mt-8 grid gap-3 md:grid-cols-2">
          {((vehicles as Vehicle[] | null) ?? []).map((vehicle) => (
            <article key={vehicle.id} className="panel rounded-3xl p-5">
              <p className="text-xs uppercase tracking-wider text-moss">
                {vehicle.kind} · {vehicle.status}
              </p>
              <h2 className="display text-2xl">{vehicle.name}</h2>
              <p className="text-sm text-ink/70">
                {vehicle.registration} · {branchName.get(vehicle.branch_id)}
                {vehicle.engine_cc ? ` · ${vehicle.engine_cc} cc` : ""}
                {vehicle.ev_range_km ? ` · ${vehicle.ev_range_km} km range` : ""}
              </p>
              <p className="mt-1 text-sm text-ink/60">
                {latest.has(vehicle.id) ? `Last odometer ${latest.get(vehicle.id)}` : "No odometer recorded yet"}
              </p>
            </article>
          ))}
        </div>
      </main>
    </div>
  );
}
