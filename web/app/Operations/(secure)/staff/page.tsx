import Link from "next/link";
import { ActionForm } from "@/components/form-error";
import { KmReturn } from "@/components/km-return";
import { confirmPickup, confirmReturn, setVehicleStatus } from "@/lib/actions";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatInr } from "@/lib/money";
import { formatWhen, liveLateFee } from "@/lib/time";
import type { Booking, Vehicle } from "@/lib/database.types";

async function pickup(_prev: string | null, formData: FormData) {
  "use server";
  const result = await confirmPickup(formData);
  return result?.error ?? null;
}

async function returned(_prev: string | null, formData: FormData) {
  "use server";
  const result = await confirmReturn(formData);
  return result?.error ?? null;
}

async function workshop(_prev: string | null, formData: FormData) {
  "use server";
  const result = await setVehicleStatus(formData);
  return result?.error ?? null;
}

type Row = Booking & { vehicles: Pick<Vehicle, "name"> | Pick<Vehicle, "name">[] };

function nameOf(row: Row) {
  const vehicle = Array.isArray(row.vehicles) ? row.vehicles[0] : row.vehicles;
  return vehicle?.name ?? "Vehicle";
}

export default async function StaffPage() {
  const profile = await requireArea("operations");
  const supabase = await createClient();
  let query = supabase
    .from("bookings")
    .select("*, vehicles(name)")
    .in("status", ["captured", "out"])
    .order("start_at");
  if (profile.role !== "admin" && profile.branch_id) {
    query = query.eq("branch_id", profile.branch_id);
  }
  const { data } = await query;
  const rows = (data ?? []) as Row[];
  const pickups = rows.filter((row) => row.status === "captured");
  const out = rows.filter((row) => row.status === "out");
  const overdue = out.filter((row) => new Date(row.end_at).getTime() < Date.now());
  const staffRole = ["manager", "sales", "mechanic", "collection"].includes(profile.role) ? profile.role : "admin";
  const seesPickup = staffRole === "admin" || staffRole === "manager" || staffRole === "sales";
  const seesReturn = staffRole === "admin" || staffRole === "manager" || staffRole === "collection";
  const seesShop = staffRole === "admin" || staffRole === "mechanic";
  const { data: shop } = seesShop
    ? await supabase.from("vehicles").select("id, name, registration, status, branch_id").eq("status", "maintenance")
    : { data: [] };

  return (
    <div className="phone px-4 py-6">
      <p className="text-xs uppercase tracking-[0.22em] text-orange-300">Staff phone</p>
      <h1 className="mt-2 text-3xl font-semibold">Counter</h1>
      <p className="mt-1 text-sm text-white/60">{profile.role} · {profile.email}</p>

      <p className="mt-4 text-xs uppercase tracking-wider text-white/40">
        <Link href="/Operations" className="underline">Desk</Link>
      </p>

      {seesPickup ? (
      <section className="mt-8">
        <h2 className="text-lg">Today&apos;s pickups</h2>
        {pickups.length === 0 ? <p className="mt-2 text-sm text-white/50">No captured bookings waiting.</p> : null}
        {pickups.map((row) => (
          <article key={row.id} className="mt-3 rounded-2xl border border-white/10 p-4">
            <p className="font-medium">{nameOf(row)}</p>
            <p className="text-sm text-white/60">{formatWhen(row.start_at)}</p>
            <ActionForm action={pickup} submit="Confirm pickup">
              <input type="hidden" name="booking_id" value={row.id} />
              <input name="odometer" type="number" required placeholder="Odometer" className="w-full rounded-xl px-3 py-2 text-black" />
            </ActionForm>
          </article>
        ))}
      </section>
      ) : null}

      {seesReturn ? (
      <>
      <section className="mt-8">
        <h2 className="text-lg">Returns</h2>
        {out.length === 0 ? <p className="mt-2 text-sm text-white/50">Nothing is out.</p> : null}
        {out.map((row) => (
          <article key={row.id} className="mt-3 rounded-2xl border border-white/10 p-4">
            <p className="font-medium">{nameOf(row)}</p>
            <p className="text-sm text-white/60">Due {formatWhen(row.end_at)}</p>
            {row.price_unit === "km" && row.odometer_out != null ? (
              <KmReturn
                bookingId={row.id}
                odometerOut={row.odometer_out}
                unitRate={Number(row.unit_rate)}
                taxRate={Number(row.tax_rate)}
                discount={Number(row.discount_amount)}
                plannedKm={row.planned_km}
                action={returned}
              />
            ) : (
              <ActionForm action={returned} submit="Confirm return">
                <input type="hidden" name="booking_id" value={row.id} />
                <input name="odometer" type="number" required placeholder="Odometer in" className="w-full rounded-xl px-3 py-2 text-black" />
              </ActionForm>
            )}
          </article>
        ))}
      </section>

      <section className="mt-8">
        <h2 className="text-lg">Live overdue</h2>
        {overdue.length === 0 ? <p className="mt-2 text-sm text-white/50">No live late fees.</p> : null}
        {overdue.map((row) => {
          if (row.price_unit === "km") {
            return (
              <article key={row.id} className="mt-3 rounded-2xl bg-orange-500/15 p-4">
                <p className="font-medium">{nameOf(row)}</p>
                <p className="text-sm">Distance is settled from the odometer, at {formatInr(Number(row.unit_rate))} per km.</p>
              </article>
            );
          }
          const late = liveLateFee(row.end_at, Number(row.hourly_price));
          return (
            <article key={row.id} className="mt-3 rounded-2xl bg-orange-500/15 p-4">
              <p className="font-medium">{nameOf(row)}</p>
              <p className="text-sm">
                {late.hours} h late · {formatInr(late.fee)} at the snapshot hourly rate
              </p>
            </article>
          );
        })}
      </section>
      </>
      ) : null}

      {seesShop ? (
        <section className="mt-8 pb-10">
          <h2 className="text-lg">Workshop</h2>
          {(shop ?? []).length === 0 ? <p className="mt-2 text-sm text-white/50">Nothing is in maintenance.</p> : null}
          {(shop ?? []).map((vehicle) => (
            <article key={vehicle.id} className="mt-3 rounded-2xl border border-white/10 p-4">
              <p className="font-medium">{vehicle.name}</p>
              <p className="text-sm text-white/60">{vehicle.registration}</p>
              <ActionForm action={workshop} submit="Mark available">
                <input type="hidden" name="vehicle_id" value={vehicle.id} />
                <input type="hidden" name="status" value="available" />
              </ActionForm>
            </article>
          ))}
        </section>
      ) : null}
    </div>
  );
}
