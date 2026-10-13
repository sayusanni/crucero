import { notFound } from "next/navigation";
import { QuoteBox } from "@/components/quote-box";
import { SiteNav } from "@/components/nav";
import { getProfile } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { defaultWindow } from "@/lib/time";
import { describeRate, formatInr } from "@/lib/money";
import type { Branch, Vehicle } from "@/lib/database.types";

export default async function VehiclePage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ start?: string; end?: string }>;
}) {
  const { id } = await params;
  const query = await searchParams;
  const fallback = defaultWindow();
  const profile = await getProfile();
  const supabase = await createClient();
  const { data: vehicle } = await supabase.from("vehicles").select("*").eq("id", id).maybeSingle();
  if (!vehicle) notFound();
  const row = vehicle as Vehicle;
  const { data: branch } = await supabase.from("branches").select("*").eq("id", row.branch_id).maybeSingle();

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="platform" />
      <main className="mx-auto grid max-w-6xl gap-8 px-5 py-12 lg:grid-cols-[1.2fr_0.8fr]">
        <div>
          <div className="h-72 rounded-3xl bg-cover bg-center" style={{ backgroundImage: `url(${row.image_url})` }} />
          <p className="mt-6 text-xs uppercase tracking-[0.22em] text-moss">
            {row.kind} · {row.category} · {(branch as Branch | null)?.name}
          </p>
          <h1 className="display mt-2 text-5xl">{row.name}</h1>
          <p className="mt-2 text-ink/70">
            {row.model} · {row.registration}
            {row.engine_cc ? ` · ${row.engine_cc} cc` : ""}
            {row.ev_range_km ? ` · ${row.ev_range_km} km range` : ""}
          </p>
          <p className="mt-4 text-sm">
            {describeRate(row.price_unit, Number(row.unit_rate), Number(row.daily_price))}. Deposit{" "}
            {formatInr(Number(row.deposit))}. The quote is stored on the booking.
            {row.price_unit === "hour"
              ? " Up to 24 hours stays hourly. After that, whole days plus the leftover hours."
              : row.price_unit === "minute"
                ? " The clock is billed in whole minutes."
                : " You enter the kilometres. The rate is this vehicle's own per-km price."}
          </p>
          <ul className="mt-4 flex flex-wrap gap-2">
            {row.features.map((feature) => (
              <li key={feature} className="rounded-full border border-ink/15 px-3 py-1 text-sm">
                {feature}
              </li>
            ))}
          </ul>
        </div>
        <QuoteBox
          vehicleId={row.id}
          start={query.start || fallback.start}
          end={query.end || fallback.end}
          signedIn={Boolean(profile)}
          priceUnit={row.price_unit}
        />
      </main>
    </div>
  );
}
