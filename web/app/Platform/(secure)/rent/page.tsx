import Link from "next/link";
import { SiteNav } from "@/components/nav";
import { getProfile } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { defaultWindow, toIso } from "@/lib/time";
import { describeRate, formatInr } from "@/lib/money";
import type { Branch, Vehicle } from "@/lib/database.types";

export default async function RentPage({
  searchParams,
}: {
  searchParams: Promise<{ branch?: string; start?: string; end?: string; kind?: string }>;
}) {
  const params = await searchParams;
  const profile = await getProfile();
  const fallback = defaultWindow();
  const start = params.start || fallback.start;
  const end = params.end || fallback.end;
  const supabase = await createClient();
  const { data: branches } = await supabase.from("branches").select("*").eq("is_active", true).order("name");
  const branchId = params.branch || (branches?.[0] as Branch | undefined)?.id || "";

  const { data: vehicles, error } = await supabase.rpc("available_vehicles", {
    p_branch: branchId || null,
    p_start: toIso(start),
    p_end: toIso(end),
    p_kind: params.kind || null,
  });

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="platform" />
      <main className="mx-auto max-w-6xl px-5 py-12">
        <h1 className="display text-5xl">What is free</h1>
        <p className="mt-2 text-ink/70">Branch, start, end, then bikes and cars that do not overlap another booking.</p>
        <form className="panel mt-8 grid gap-3 rounded-3xl p-4 md:grid-cols-5">
          <label className="text-sm">
            Branch
            <select name="branch" defaultValue={branchId} className="mt-1 w-full rounded-xl px-3 py-2">
              {(branches as Branch[] | null)?.map((branch) => (
                <option key={branch.id} value={branch.id}>
                  {branch.name}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            Start
            <input name="start" type="datetime-local" defaultValue={start} className="mt-1 w-full rounded-xl px-3 py-2" />
          </label>
          <label className="text-sm">
            End
            <input name="end" type="datetime-local" defaultValue={end} className="mt-1 w-full rounded-xl px-3 py-2" />
          </label>
          <label className="text-sm">
            Kind
            <select name="kind" defaultValue={params.kind || ""} className="mt-1 w-full rounded-xl px-3 py-2">
              <option value="">Bikes and cars</option>
              <option value="bike">Bikes</option>
              <option value="car">Cars</option>
            </select>
          </label>
          <button className="mt-5 rounded-xl bg-ink px-4 py-2 text-paper">Show vehicles</button>
        </form>
        {error ? <p className="mt-6 text-ember">{error.message}</p> : null}
        <div className="mt-8 grid gap-4 md:grid-cols-2">
          {((vehicles as Vehicle[] | null) ?? []).map((vehicle) => (
            <article key={vehicle.id} className="panel overflow-hidden rounded-3xl">
              <div className="h-40 bg-cover bg-center" style={{ backgroundImage: `url(${vehicle.image_url})` }} />
              <div className="p-5">
                <p className="text-xs uppercase tracking-[0.18em] text-moss">
                  {vehicle.kind} · {vehicle.category}
                </p>
                <h2 className="display text-2xl">
                  {vehicle.name} <span className="text-lg text-ink/60">{vehicle.model}</span>
                </h2>
                <p className="mt-1 text-sm text-ink/65">
                  {describeRate(vehicle.price_unit, Number(vehicle.unit_rate), Number(vehicle.daily_price))} · deposit{" "}
                  {formatInr(Number(vehicle.deposit))}
                </p>
                <Link
                  href={`/Platform/vehicles/${vehicle.id}?start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}`}
                  className="mt-4 inline-block rounded-full bg-ember px-4 py-2 text-sm text-paper"
                >
                  Details and price
                </Link>
              </div>
            </article>
          ))}
        </div>
      </main>
    </div>
  );
}
