import { SiteNav } from "@/components/nav";
import { requireArea } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { formatInr, formatInrExact } from "@/lib/money";
import { liveLateFee } from "@/lib/time";
import type { Booking } from "@/lib/database.types";

export default async function ReportsPage() {
  const profile = await requireArea("reports");
  const supabase = await createClient();
  const [{ data: bookings }, { data: branches }, { data: vehicles }, { data: lines }] = await Promise.all([
    supabase.from("bookings").select("branch_id, status, rental_total, end_at, hourly_price"),
    supabase.from("branches").select("id, name"),
    supabase.from("vehicles").select("status"),
    supabase.from("journal_lines").select("account_code, credit").in("account_code", ["4000", "4100"]),
  ]);
  const rows = (bookings ?? []) as Pick<Booking, "branch_id" | "status" | "rental_total" | "end_at" | "hourly_price">[];
  const recognized = (lines ?? [])
    .filter((line) => line.account_code === "4000")
    .reduce((total, line) => total + Number(line.credit), 0);
  const late = (lines ?? [])
    .filter((line) => line.account_code === "4100")
    .reduce((total, line) => total + Number(line.credit), 0);

  const byStatus = new Map<string, number>();
  const byBranch = new Map<string, { name: string; count: number; quoted: number }>();
  for (const branch of branches ?? []) byBranch.set(branch.id, { name: branch.name, count: 0, quoted: 0 });
  let overdueFee = 0;
  let overdueCount = 0;
  for (const booking of rows) {
    if (booking.status === "cancelled") continue;
    byStatus.set(booking.status, (byStatus.get(booking.status) ?? 0) + 1);
    const branch = byBranch.get(booking.branch_id);
    if (branch) {
      branch.count += 1;
      branch.quoted += Number(booking.rental_total);
    }
    if (booking.status === "out" && new Date(booking.end_at).getTime() < Date.now()) {
      overdueCount += 1;
      overdueFee += liveLateFee(booking.end_at, Number(booking.hourly_price)).fee;
    }
  }
  const fleet = { available: 0, maintenance: 0 };
  for (const vehicle of vehicles ?? []) {
    if (vehicle.status === "maintenance") fleet.maintenance += 1;
    else fleet.available += 1;
  }

  return (
    <div className="yard min-h-svh">
      <SiteNav profile={profile} area="reports" />
      <main className="mx-auto max-w-5xl px-5 py-12">
        <p className="text-xs uppercase tracking-[0.22em] text-ember">/Reports</p>
        <h1 className="display mt-3 text-5xl">What the company did</h1>
        <p className="mt-3 max-w-xl text-ink/70">
          Quoted rental totals are what customers were shown. Recognized revenue is what the journal has posted.
        </p>
        <div className="mt-8 grid gap-4 md:grid-cols-3">
          {[
            ["Recognized rental revenue", formatInrExact(recognized)],
            ["Recognized late fees", formatInr(late)],
            ["Live overdue, not yet posted", `${overdueCount} · ${formatInr(overdueFee)}`],
          ].map(([label, value]) => (
            <article key={label} className="panel rounded-3xl p-5">
              <p className="text-xs uppercase tracking-wider text-ink/50">{label}</p>
              <p className="display mt-2 text-3xl">{value}</p>
            </article>
          ))}
        </div>
        <section className="mt-10">
          <h2 className="display text-2xl">Bookings by status</h2>
          <div className="mt-3 flex flex-wrap gap-2">
            {[...byStatus.entries()].map(([status, count]) => (
              <span key={status} className="panel rounded-full px-4 py-2 text-sm">
                {status} · {count}
              </span>
            ))}
            {byStatus.size === 0 ? <p className="text-sm text-ink/60">No bookings yet.</p> : null}
          </div>
        </section>
        <section className="mt-10">
          <h2 className="display text-2xl">Branches</h2>
          <div className="mt-3 grid gap-3 md:grid-cols-3">
            {[...byBranch.values()].map((branch) => (
              <article key={branch.name} className="panel rounded-3xl p-5">
                <h3 className="display text-2xl">{branch.name}</h3>
                <p className="mt-1 text-sm text-ink/70">
                  {branch.count} {branch.count === 1 ? "booking" : "bookings"} · quoted {formatInr(branch.quoted)}
                </p>
              </article>
            ))}
          </div>
        </section>
        <section className="mt-10">
          <h2 className="display text-2xl">Fleet</h2>
          <p className="mt-2 text-sm text-ink/70">
            {fleet.available} available · {fleet.maintenance} in maintenance
          </p>
        </section>
      </main>
    </div>
  );
}
