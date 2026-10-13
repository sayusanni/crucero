import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatInr } from "@/lib/money";
import { formatWhen } from "@/lib/time";
import type { Booking } from "@/lib/database.types";

export default async function AdminBookingsPage() {
  const profile = await requireArea("operations");
  const supabase = await createClient();
  const { data } = await supabase
    .from("bookings")
    .select("*, vehicles(name), branches(name), profiles(full_name, email)")
    .order("created_at", { ascending: false });

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="operations" />
      <main className="mx-auto max-w-5xl px-5 py-12">
        <h1 className="display text-5xl">Bookings</h1>
        <div className="mt-8 space-y-3">
          {(data ?? []).map((row) => {
            const booking = row as Booking & {
              vehicles: { name: string } | { name: string }[];
              branches: { name: string } | { name: string }[];
              profiles: { full_name: string; email: string | null } | { full_name: string; email: string | null }[];
            };
            const vehicle = Array.isArray(booking.vehicles) ? booking.vehicles[0] : booking.vehicles;
            const branch = Array.isArray(booking.branches) ? booking.branches[0] : booking.branches;
            const customer = Array.isArray(booking.profiles) ? booking.profiles[0] : booking.profiles;
            return (
              <article key={booking.id} className="panel rounded-2xl p-4 text-sm">
                <p className="text-xs uppercase tracking-wider text-ember">{booking.status}</p>
                <p className="font-medium">
                  {vehicle?.name} · {branch?.name}
                </p>
                <p className="text-ink/70">
                  {customer?.full_name || customer?.email} · {formatWhen(booking.start_at)} → {formatWhen(booking.end_at)}
                </p>
                <p>
                  Rental {formatInr(Number(booking.rental_total))} · GST {formatInr(Number(booking.tax_amount))} · deposit{" "}
                  {formatInr(Number(booking.deposit_amount))}
                </p>
              </article>
            );
          })}
        </div>
      </main>
    </div>
  );
}
