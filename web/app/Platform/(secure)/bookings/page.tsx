import Link from "next/link";
import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatInr } from "@/lib/money";
import { formatWhen } from "@/lib/time";
import type { Booking, Vehicle } from "@/lib/database.types";

export default async function BookingsPage({ searchParams }: { searchParams: Promise<{ captured?: string }> }) {
  const profile = await requireArea("platform");
  const params = await searchParams;
  const supabase = await createClient();
  const { data } = await supabase
    .from("bookings")
    .select("*, vehicles(name, kind)")
    .eq("customer_id", profile.id)
    .order("created_at", { ascending: false });

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="platform" />
      <main className="mx-auto max-w-3xl px-5 py-12">
        <h1 className="display text-5xl">My bookings</h1>
        {params.captured ? (
          <p className="mt-4 rounded-2xl bg-moss/10 px-4 py-3 text-sm">
            Payment captured. Rental revenue and the deposit were posted as separate journal lines.
          </p>
        ) : null}
        <div className="mt-8 space-y-3">
          {(data ?? []).map((row) => {
            const booking = row as Booking & { vehicles: Pick<Vehicle, "name" | "kind"> | Pick<Vehicle, "name" | "kind">[] };
            const vehicle = Array.isArray(booking.vehicles) ? booking.vehicles[0] : booking.vehicles;
            return (
              <article key={booking.id} className="panel rounded-3xl p-5">
                <p className="text-xs uppercase tracking-wider text-ember">{booking.status}</p>
                <h2 className="display text-2xl">{vehicle?.name}</h2>
                <p className="text-sm text-ink/70">
                  {formatWhen(booking.start_at)} → {formatWhen(booking.end_at)}
                  <br />
                  Rental {formatInr(Number(booking.rental_total))} · deposit {formatInr(Number(booking.deposit_amount))}
                </p>
                {booking.status === "draft" ? (
                  <Link href={`/Platform/book/${booking.id}/documents`} className="mt-3 inline-block text-sm underline">
                    Upload documents
                  </Link>
                ) : null}
                {booking.status === "authorized" || booking.status === "signed" ? (
                  <Link href={`/Platform/book/${booking.id}/agreement`} className="mt-3 inline-block text-sm underline">
                    {booking.status === "authorized" ? "Sign the agreement" : "Capture payment"}
                  </Link>
                ) : null}
                <p className="mt-2 text-xs text-ink/55">
                  Snapshot {booking.billed_days} day{booking.billed_days === 1 ? "" : "s"} + {booking.remainder_hours} h · GST{" "}
                  {booking.tax_rate}% · authorize {formatInr(Number(booking.authorize_amount))}
                </p>
              </article>
            );
          })}
        </div>
      </main>
    </div>
  );
}
